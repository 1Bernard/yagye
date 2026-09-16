defmodule YagyeCore.Settlement.Workers.BankDispatchWorker do
  @moduledoc """
  Sends the settled batch gross amount to the merchant's bank via the provider
  disbursement API, then posts the closing ledger entry.

  Enqueued atomically within `SettlementProcessorWorker`'s Multi after a batch
  reaches the `settled` state. Idempotent: if `bank_dispatch_ref` is already set
  the job exits cleanly without re-dispatching.
  """

  use Oban.Worker, queue: :settlement, max_attempts: 5

  require Logger

  alias Ecto.Multi
  alias YagyeCore.Ledger
  alias YagyeCore.Outbox
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
      with {:ok, credential} <-
             Providers.fetch_credential_for_status_check(batch.provider_id, nil, batch.mode),
           {:ok, disbursement_ref} <- call_disbursement_api(batch, credential) do
        confirm_dispatch(batch, disbursement_ref)
      else
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
        merchant_code: b.merchant_id,
        provider_code: b.provider_id,
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

  defp call_disbursement_api(batch, credential) do
    base_url = credential["base_url"]
    api_key = credential["api_key"] || credential["secret_key"] || ""

    body = %{
      amount_minor: batch.gross_amount,
      currency: batch.currency,
      destination_type: "BANK",
      destination_ref: "merchant_#{batch.merchant_id}"
    }

    opts =
      [
        json: body,
        headers: [{"x-api-key", api_key}],
        receive_timeout: 15_000
      ] ++ Application.get_env(:yagye_core, :simulator_req_opts, [])

    case Req.post(base_url <> "/disbursements", opts) do
      {:ok, %Req.Response{status: 201, body: %{"disbursement_ref" => ref}}} ->
        {:ok, ref}

      {:ok, %Req.Response{status: status, body: resp_body}} ->
        Logger.warning("[BankDispatchWorker] disbursement API error",
          status: status,
          body: inspect(resp_body)
        )

        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, {:network_error, reason}}
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
        merchant_code: b.merchant_id,
        provider_code: b.provider_id,
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
