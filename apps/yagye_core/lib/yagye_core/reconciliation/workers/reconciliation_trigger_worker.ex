defmodule YagyeCore.Reconciliation.Workers.ReconciliationTriggerWorker do
  @moduledoc false

  # Receives a "settlement.batch.settled" outbox envelope and starts a
  # reconciliation run scoped to the batch's settlement period.
  # For native-rail providers, first fetches and ingests the settlement report
  # from the simulator so the matching engine has right-side data.

  use Oban.Worker, queue: :reconciliation, max_attempts: 3

  require Logger

  alias YagyeCore.Providers.Schemas.Provider
  alias YagyeCore.Reconciliation
  alias YagyeCore.Reconciliation.Reports.SimulatorReport
  alias YagyeCore.Repo
  alias YagyeCore.Settlement.Schemas.SettlementBatch

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"envelope" => envelope}}) do
    batch_id = envelope["payload"]["settlement_code"]
    batch = Repo.get!(SettlementBatch, batch_id)
    provider = Repo.get!(Provider, batch.provider_id)

    if provider.kind == "native_rail" do
      ingest_settlement_report(batch)

      case Reconciliation.start_run(
             "settlement",
             batch.mode,
             batch.period_start,
             batch.period_end,
             provider_id: batch.provider_id,
             merchant_id: batch.merchant_id,
             currency: batch.currency
           ) do
        {:ok, _run} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      :ok
    end
  end

  defp ingest_settlement_report(batch) do
    start_date = DateTime.to_date(batch.period_start)
    end_date = DateTime.to_date(batch.period_end)
    Enum.each(Date.range(start_date, end_date), &ingest_one_day(batch, &1))
  end

  defp ingest_one_day(batch, date) do
    case SimulatorReport.generate(batch.provider_id, batch.mode, date) do
      {:ok, payload} ->
        ingest_report_payload(batch, payload, date)

      {:error, reason} ->
        Logger.warning("[ReconciliationTriggerWorker] report fetch failed",
          reason: inspect(reason),
          batch_id: batch.id,
          date: date
        )
    end
  end

  defp ingest_report_payload(batch, payload, date) do
    case Reconciliation.ingest_report(batch.provider_id, payload) do
      {:ok, _} ->
        :ok

      {:error, {:already_ingested, _}} ->
        :ok

      {:error, reason} ->
        Logger.warning("[ReconciliationTriggerWorker] report ingest failed",
          reason: inspect(reason),
          batch_id: batch.id,
          date: date
        )
    end
  end
end
