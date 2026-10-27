defmodule YagyeCore.Reconciliation.Workers.ReconciliationSettlementWorker do
  @moduledoc false

  # Triggered by "reconciliation.run.completed" outbox events.
  # For settlement-kind runs, sums provider-reported net amounts and publishes
  # a "settlement.batch.recon_result" event so the portal can advance the
  # settlement state to "reconciled" (no breaks) or "reconciling" (open breaks)
  # and display the Reported net / Variance figures.

  use Oban.Worker, queue: :reconciliation, max_attempts: 3

  require Logger

  import Ecto.Query

  alias YagyeCore.Merchants
  alias YagyeCore.Outbox
  alias YagyeCore.Providers

  alias YagyeCore.Reconciliation.Schemas.{
    ProviderReportLine,
    ProviderSettlementReport,
    ReconciliationRun
  }

  alias YagyeCore.Repo
  alias YagyeCore.Settlement.Schemas.SettlementBatch

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"envelope" => envelope}}) do
    run_id = envelope["payload"]["run_id"]
    run = Repo.get!(ReconciliationRun, run_id)

    if run.kind == "settlement" do
      close_settlement(run)
    else
      :ok
    end
  end

  # ── Private ──────────────────────────────────────────────────────────────────

  defp close_settlement(run) do
    case find_batch(run) do
      nil ->
        Logger.warning("[ReconciliationSettlementWorker] no batch for run",
          run_id: run.id,
          provider_id: run.provider_id,
          scope_from: run.scope_from,
          scope_to: run.scope_to
        )

        :ok

      batch ->
        reported_net = sum_reported_net(run)
        state = if run.break_count == 0, do: "reconciled", else: "reconciling"

        Outbox.build_changeset(batch, "settlement.batch.recon_result", %{
          settlement_code: batch.id,
          merchant_code: resolve_merchant_code(batch.merchant_id),
          provider_code: resolve_provider_code(batch.provider_id),
          mode: batch.mode,
          state: state,
          currency: batch.currency,
          net_amount: batch.net_amount,
          reported_net: reported_net,
          variance: batch.net_amount - (reported_net || 0),
          period_start: batch.period_start && DateTime.to_iso8601(batch.period_start),
          period_end: batch.period_end && DateTime.to_iso8601(batch.period_end),
          item_count: batch.payment_count,
          break_count: run.break_count,
          matched_count: run.matched_count
        })
        |> Repo.insert()
        |> case do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp find_batch(run) do
    query =
      from(b in SettlementBatch,
        where: b.provider_id == ^run.provider_id,
        where: b.period_start == ^run.scope_from,
        where: b.period_end == ^run.scope_to
      )

    query =
      if run.merchant_id,
        do: where(query, [b], b.merchant_id == ^run.merchant_id),
        else: where(query, [b], is_nil(b.merchant_id))

    Repo.one(query)
  end

  defp sum_reported_net(run) do
    start_date = DateTime.to_date(run.scope_from)
    end_date = DateTime.to_date(run.scope_to)

    from(l in ProviderReportLine,
      join: r in ProviderSettlementReport,
      on: l.report_id == r.id,
      where: r.provider_id == ^run.provider_id,
      where: r.mode == ^run.mode,
      where: l.value_date >= ^start_date,
      where: l.value_date <= ^end_date,
      select: sum(l.net_amount)
    )
    |> Repo.one()
  end

  defp resolve_provider_code(provider_id) do
    case Providers.get_provider(provider_id) do
      {:ok, provider} -> provider.code
      _ -> nil
    end
  end

  defp resolve_merchant_code(nil), do: nil

  defp resolve_merchant_code(merchant_id) do
    case Merchants.get_merchant_by_id(merchant_id) do
      {:ok, merchant} -> merchant.public_id
      _ -> nil
    end
  end
end
