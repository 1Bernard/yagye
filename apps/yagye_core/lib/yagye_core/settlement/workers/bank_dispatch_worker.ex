defmodule YagyeCore.Settlement.Workers.BankDispatchWorker do
  @moduledoc """
  Sends the settled batch gross amount to the merchant via the appropriate
  disbursement route, then posts the closing ledger entry.

  Routing is driven by the merchant's settlement controls:
  - settlement_msisdn set     → mobile money via the batch provider's disburse/2
  - bank account fields set   → bank transfer via Paystack's Transfers API
  - simulation mode           → fake ref, no real API call

  Enqueued atomically within `SettlementProcessorWorker`'s Multi after a batch
  reaches the `settled` state. Idempotent: if `bank_dispatch_ref` is already set
  the job exits cleanly without re-dispatching.
  """

  use Oban.Worker, queue: :settlement, max_attempts: 5

  require Logger

  alias Ecto.Multi
  alias YagyeCore.Ledger
  alias YagyeCore.Merchants
  alias YagyeCore.Outbox
  alias YagyeCore.Payments.ProviderAdapter
  alias YagyeCore.Providers
  alias YagyeCore.Repo
  alias YagyeCore.Settlement
  alias YagyeCore.Settlement.Schemas.SettlementBatch

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"batch_id" => batch_id}}) do
    batch = Repo.get!(SettlementBatch, batch_id)
    dispatch(batch)
  end

  # ── Private ──────────────────────────────────────────────────────────────────

  defp dispatch(%SettlementBatch{bank_dispatch_ref: ref}) when is_binary(ref) do
    :ok
  end

  defp dispatch(%SettlementBatch{} = batch) do
    if batch.dispatch_approved_by || gate_cleared?(batch) do
      result =
        if batch.mode == "simulation" do
          {:ok, "sim_disb_#{batch.id}"}
        else
          controls = Settlement.get_settlement_controls(batch.merchant_id)
          route_disbursement(batch, controls)
        end

      case result do
        {:ok, disbursement_ref} ->
          confirm_dispatch(batch, disbursement_ref)

        {:error, reason} ->
          Logger.error("[BankDispatchWorker] dispatch failed",
            batch_id: batch.id,
            reason: inspect(reason)
          )

          {:error, reason}
      end
    else
      enter_approval_gate(batch)
    end
  end

  # Mobile money — use the batch provider's disburse/2 (e.g. MTN Disbursements API)
  defp route_disbursement(batch, %{settlement_msisdn: msisdn})
       when is_binary(msisdn) and msisdn != "" do
    with {:ok, credential} <-
           Providers.fetch_credential_for_status_check(batch.provider_id, nil, batch.mode) do
      call_mobile_disbursement(batch, msisdn, credential)
    end
  end

  # Bank account — use Paystack Transfers API regardless of collection provider
  defp route_disbursement(
         batch,
         %{
           settlement_bank_code: bank_code,
           settlement_account_number: account_number,
           settlement_account_name: name
         }
       )
       when is_binary(bank_code) and is_binary(account_number) do
    with {:ok, credential} <- fetch_paystack_credential(batch.mode) do
      call_bank_disbursement(batch, bank_code, account_number, name, credential)
    end
  end

  defp route_disbursement(_batch, _controls) do
    {:error, :no_settlement_method}
  end

  defp gate_cleared?(%SettlementBatch{} = batch) do
    case Settlement.get_settlement_controls(batch.merchant_id) do
      nil -> true
      %{approval_threshold: nil} -> true
      %{approval_threshold: threshold} -> batch.gross_amount < threshold
    end
  end

  defp enter_approval_gate(%SettlementBatch{} = batch) do
    Multi.new()
    |> Multi.update(:batch, SettlementBatch.awaiting_approval_changeset(batch))
    |> Multi.insert(:outbox, fn %{batch: b} ->
      Outbox.build_changeset(b, "settlement.batch.awaiting_approval", %{
        settlement_code: b.id,
        merchant_code: resolve_merchant_code(b.merchant_id),
        provider_code: resolve_provider_code(b.provider_id),
        mode: b.mode,
        state: "awaiting_approval",
        currency: b.currency,
        gross_amount: b.gross_amount,
        period_start: b.period_start && DateTime.to_iso8601(b.period_start),
        period_end: b.period_end && DateTime.to_iso8601(b.period_end)
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, _} -> :ok
      {:error, _step, reason, _} -> {:error, reason}
    end
  end

  defp call_mobile_disbursement(batch, msisdn, credential) do
    with {:ok, provider} <- Providers.get_provider(batch.provider_id) do
      adapter = ProviderAdapter.for_provider(provider)
      :code.ensure_loaded(adapter)

      if function_exported?(adapter, :disburse, 2) do
        params = %{
          amount: batch.gross_amount,
          currency: batch.currency,
          reference: batch.id,
          recipient_msisdn: msisdn
        }

        run_disburse(adapter, params, credential)
      else
        Logger.warning("[BankDispatchWorker] provider #{provider.code} has no disburse/2",
          batch_id: batch.id
        )

        {:error, :no_disburse_impl}
      end
    end
  end

  defp call_bank_disbursement(batch, bank_code, account_number, name, credential) do
    params = %{
      amount: batch.gross_amount,
      currency: batch.currency,
      reference: batch.id,
      recipient_bank_code: bank_code,
      recipient_account_number: account_number,
      recipient_name: name || ""
    }

    run_disburse(YagyeCore.Payments.Adapters.PaystackAdapter, params, credential)
  end

  defp fetch_paystack_credential(mode) do
    Providers.fetch_credential_for_psp("paystack", mode)
  end

  defp resolve_provider_code(provider_id) do
    case Providers.get_provider(provider_id) do
      {:ok, provider} -> provider.code
      _ -> nil
    end
  end

  defp resolve_merchant_code(merchant_id) do
    case Merchants.get_merchant_by_id(merchant_id) do
      {:ok, merchant} -> merchant.public_id
      _ -> nil
    end
  end

  defp run_disburse(adapter, params, credential) do
    case adapter.disburse(params, credential) do
      {:ok, %{provider_reference: ref}} -> {:ok, ref}
      {:pending, %{provider_reference: ref}} -> {:ok, ref}
      {:error, _} = err -> err
    end
  end

  defp confirm_dispatch(batch, disbursement_ref) do
    now = DateTime.utc_now()

    Multi.new()
    |> Multi.update(
      :batch,
      SettlementBatch.dispatch_changeset(batch, %{
        dispatch_ref: disbursement_ref,
        dispatched_at: now
      })
    )
    |> Multi.run(:ledger, fn _repo, _ ->
      Ledger.post_batch_dispatched(batch)
    end)
    |> Multi.insert(:outbox, fn %{batch: b} ->
      Outbox.build_changeset(b, "settlement.batch.dispatched", %{
        settlement_code: b.id,
        merchant_code: resolve_merchant_code(b.merchant_id),
        provider_code: resolve_provider_code(b.provider_id),
        mode: b.mode,
        state: "dispatched",
        currency: b.currency,
        gross_amount: b.gross_amount,
        bank_dispatch_ref: b.bank_dispatch_ref,
        bank_dispatched_at: b.bank_dispatched_at && DateTime.to_iso8601(b.bank_dispatched_at),
        period_start: b.period_start && DateTime.to_iso8601(b.period_start),
        period_end: b.period_end && DateTime.to_iso8601(b.period_end)
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, _} -> :ok
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end
end
