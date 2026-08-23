defmodule YagyeCore.Settlement.Workers.SettlementProcessorWorker do
  @moduledoc false

  use Oban.Worker, queue: :settlement, max_attempts: 3

  require OpenTelemetry.Tracer

  alias Ecto.Multi
  alias YagyeCore.Ledger
  alias YagyeCore.Outbox
  alias YagyeCore.Repo
  alias YagyeCore.Settlement
  alias YagyeCore.Settlement.Schemas.SettlementBatch

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
    result =
      Multi.new()
      |> Multi.update(:processing, SettlementBatch.transition_changeset(batch, "processing"))
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
          batch_id: b.id,
          merchant_id: b.merchant_id,
          provider_id: b.provider_id,
          currency: b.currency,
          payment_count: b.payment_count,
          gross_amount: b.gross_amount,
          settled_at: b.settled_at
        })
      end)
      |> Repo.transaction()

    case result do
      {:ok, %{settled: settled_batch}} ->
        # Best-effort: create the Settlement + SettlementItems for reconciliation.
        # Failure here does not roll back the batch settlement.
        case Settlement.create_settlement_from_batch(settled_batch) do
          {:ok, _} -> :ok
          {:error, reason} -> {:warning, "settlement record creation failed: #{inspect(reason)}"}
        end

        {:ok, settled_batch}

      {:error, _step, reason, _changes} ->
        mark_failed(batch, reason)
        {:error, reason}
    end
  end

  defp mark_failed(%SettlementBatch{} = batch, reason) do
    batch
    |> SettlementBatch.transition_changeset("failed")
    |> Ecto.Changeset.put_change(:error, inspect(reason))
    |> Repo.update()
  end
end
