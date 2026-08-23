defmodule YagyeCore.Reconciliation.Workers.ReconciliationTriggerWorker do
  @moduledoc false

  # Receives a "settlement.batch.settled" outbox envelope and starts a
  # reconciliation run scoped to the batch's settlement period.

  use Oban.Worker, queue: :reconciliation, max_attempts: 3

  alias YagyeCore.Reconciliation
  alias YagyeCore.Repo
  alias YagyeCore.Settlement.Schemas.SettlementBatch

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"envelope" => envelope}}) do
    batch_id = envelope["payload"]["batch_id"]
    batch = Repo.get!(SettlementBatch, batch_id)

    case Reconciliation.start_run(
           "batch",
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
  end
end
