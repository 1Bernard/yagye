defmodule YagyeCore.Settlement.Workers.SettlementProcessorWorker do
  @moduledoc false

  use Oban.Worker, queue: :settlement, max_attempts: 3

  require OpenTelemetry.Tracer

  alias Ecto.Multi
  alias YagyeCore.Ledger
  alias YagyeCore.Merchants.Schemas.Merchant
  alias YagyeCore.Outbox
  alias YagyeCore.Pricing
  alias YagyeCore.Providers.Schemas.Provider
  alias YagyeCore.Repo
  alias YagyeCore.Settlement
  alias YagyeCore.Settlement.Schemas.SettlementBatch
  alias YagyeCore.Settlement.Workers.BankDispatchWorker

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"settlement_batch_id" => id}}) do
    OpenTelemetry.Tracer.with_span "settlement.process_batch" do
      batch = Repo.get!(SettlementBatch, id)
      process(batch)
    end
  end

  # Already terminal — idempotent no-op.
  defp process(%SettlementBatch{state: state}) when state in ["settled", "failed"], do: :ok

  defp process(%SettlementBatch{} = batch) do
    fee_totals = compute_fee_totals(batch)
    cross_net_amount = compute_cross_net_amount(batch)
    net_after_cross_net = fee_totals.expected_net - cross_net_amount

    result =
      Multi.new()
      |> Multi.update(
        :processing,
        batch
        |> SettlementBatch.transition_changeset("processing")
        |> Ecto.Changeset.put_change(:platform_fees, fee_totals.expected_platform_fees)
        |> Ecto.Changeset.put_change(:net_amount, net_after_cross_net)
        |> Ecto.Changeset.put_change(:reserved_amount, Map.get(fee_totals, :reserved_amount, 0))
      )
      |> Multi.run(:ledger, fn _repo, %{processing: b} ->
        Ledger.post_batch_approved(b)
      end)
      |> Multi.update(:settled, fn %{processing: b} ->
        b
        |> SettlementBatch.transition_changeset("settled")
        |> Ecto.Changeset.put_change(:settled_at, DateTime.utc_now())
      end)
      |> Multi.insert(:outbox_settled, fn %{settled: b} ->
        Outbox.build_changeset(b, "settlement.batch.settled", %{
          settlement_code: b.id,
          merchant_code: merchant_code(b.merchant_id),
          provider_code: provider_code(b.provider_id),
          mode: b.mode,
          state: "settled",
          currency: b.currency,
          payment_count: b.payment_count,
          gross_amount: b.gross_amount,
          platform_fees: b.platform_fees,
          net_amount: b.net_amount,
          period_start: b.period_start && DateTime.to_iso8601(b.period_start),
          period_end: b.period_end && DateTime.to_iso8601(b.period_end),
          settled_at: b.settled_at && DateTime.to_iso8601(b.settled_at)
        })
      end)
      |> Multi.run(:bank_dispatch_job, fn _repo, %{settled: b} ->
        BankDispatchWorker.new(%{batch_id: b.id}) |> Oban.insert()
      end)
      |> Repo.transaction()

    case result do
      {:ok, %{settled: settled_batch}} ->
        try_record_settlement(settled_batch, cross_net_amount)
        {:ok, settled_batch}

      {:error, _step, reason, _changes} ->
        mark_failed(batch, reason)
        {:error, reason}
    end
  end

  defp compute_fee_totals(batch) do
    case Settlement.compute_batch_fee_totals(batch) do
      {:ok, totals} -> totals
      _ -> %{expected_platform_fees: 0, expected_net: batch.gross_amount}
    end
  end

  # Returns the pending cross_net orchestration fee amount for this merchant.
  # Zero when billing method is not cross_net or no uncollected fees exist.
  defp compute_cross_net_amount(%SettlementBatch{} = batch) do
    merchant = Repo.get!(Merchant, batch.merchant_id)

    if merchant.orchestration_billing_method == "cross_net" do
      case Pricing.pending_orchestration_fees(batch.merchant_id, batch.currency, batch.mode) do
        {:ok, amount} -> amount
        _ -> 0
      end
    else
      0
    end
  end

  # Best-effort: create the Settlement + SettlementItems for reconciliation,
  # and (when cross_net_amount > 0) create the platform_fee_invoice.
  # Failure here does not roll back the batch settlement.
  defp try_record_settlement(settled_batch, cross_net_amount) do
    case Settlement.create_settlement_from_batch(settled_batch) do
      {:ok, %{settlement: settlement}} ->
        if cross_net_amount > 0 do
          Pricing.create_cross_net_invoice(
            settled_batch.merchant_id,
            settled_batch.mode,
            settled_batch.currency,
            cross_net_amount,
            settlement.id
          )
        end

        :ok

      {:error, reason} ->
        {:warning, "settlement record creation failed: #{inspect(reason)}"}
    end
  end

  defp mark_failed(%SettlementBatch{} = batch, reason) do
    batch
    |> SettlementBatch.transition_changeset("failed")
    |> Ecto.Changeset.put_change(:error, inspect(reason))
    |> Repo.update()
  end

  defp merchant_code(merchant_id) do
    case Repo.get(Merchant, merchant_id) do
      %Merchant{public_id: code} -> code
      nil -> nil
    end
  end

  defp provider_code(provider_id) do
    case Repo.get(Provider, provider_id) do
      %Provider{code: code} -> code
      nil -> nil
    end
  end
end
