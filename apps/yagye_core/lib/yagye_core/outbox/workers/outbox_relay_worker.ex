defmodule YagyeCore.Outbox.Workers.OutboxRelayWorker do
  @moduledoc false

  # Reads undelivered outbox_messages in id order (guaranteed insertion order)
  # and dispatches them to the appropriate downstream worker.
  #
  # At P7: destination "internal:projections" → dispatches projection workers.
  # At P14: "kafka:*" destinations will be added here to publish to Kafka topics.
  #
  # Scheduled via Oban cron (see Application). Self-reschedules immediately
  # when a full batch is found so bursts drain without waiting for the next tick.

  use Oban.Worker, queue: :events, max_attempts: 1

  import Ecto.Query

  alias YagyeCore.Outbox.EventEnvelope
  alias YagyeCore.Outbox.Schemas.OutboxMessage
  alias YagyeCore.Projections.Workers.{MerchantBalanceProjection, PaymentSummaryProjection}
  alias YagyeCore.Reconciliation.Workers.ReconciliationTriggerWorker
  alias YagyeCore.Repo

  @batch_size 50

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    messages = fetch_batch()
    Enum.each(messages, &dispatch/1)

    if length(messages) == @batch_size do
      # Full batch — more rows likely waiting, schedule immediately
      __MODULE__.new(%{}) |> Oban.insert()
    end

    :ok
  end

  # ── Private ──────────────────────────────────────────────────────────────────

  defp fetch_batch do
    from(m in OutboxMessage,
      where: is_nil(m.published_at),
      order_by: [asc: m.id],
      limit: @batch_size,
      lock: "FOR UPDATE SKIP LOCKED"
    )
    |> Repo.all()
  end

  defp dispatch(%OutboxMessage{destination: "internal:projections"} = msg) do
    envelope = EventEnvelope.from_map(msg.envelope)

    workers = projection_workers_for(envelope.event_type)

    results =
      Enum.map(workers, fn worker ->
        worker.new(%{"outbox_id" => msg.id, "envelope" => msg.envelope})
        |> Oban.insert()
      end)

    if Enum.all?(results, &match?({:ok, _}, &1)) do
      msg |> OutboxMessage.mark_published_changeset() |> Repo.update()
    else
      msg |> OutboxMessage.mark_failed_changeset(:dispatch_error) |> Repo.update()
    end
  end

  defp dispatch(%OutboxMessage{} = msg) do
    # P14: kafka:* destinations handled here
    msg |> OutboxMessage.mark_failed_changeset(:unknown_destination) |> Repo.update()
  end

  # Maps event_type → list of projection workers that care about it
  defp projection_workers_for(event_type) do
    []
    |> maybe_add(String.starts_with?(event_type, "payment."), PaymentSummaryProjection)
    |> maybe_add(
      event_type in ~w[payment.succeeded payment.failed payment.refunded],
      MerchantBalanceProjection
    )
    |> maybe_add(event_type == "settlement.batch.settled", ReconciliationTriggerWorker)
  end

  defp maybe_add(list, true, worker), do: [worker | list]
  defp maybe_add(list, false, _worker), do: list
end
