defmodule YagyeCore.Outbox.KafkaProducer do
  @moduledoc false

  # Publishes an EventEnvelope to the appropriate Redpanda topic.
  #
  # Topic routing is prefix-based on event_type (e.g. "payment.*" → yagye.payments.v1).
  # Messages are partitioned by merchant_id (or aggregate_id when merchant_id is nil)
  # so all events for the same merchant land on the same partition in order.
  #
  # Swapped out for YagyeCore.Outbox.KafkaProducer.Stub in test via config.

  require Logger

  alias YagyeCore.Outbox.EventEnvelope

  @client :yagye_kafka_client

  @topics [
    {"payment.", "yagye.payments.v1"},
    {"merchant.", "yagye.applications.v1"},
    {"api_key.", "yagye.api_keys.v1"},
    {"webhook.", "yagye.webhooks.v1"},
    {"dispute.", "yagye.disputes.v1"},
    {"adjustment_approval.", "yagye.adjustment_approvals.v1"},
    {"payout.", "yagye.payouts.v1"},
    {"settlement.", "yagye.settlements.v1"}
  ]

  def publish(%EventEnvelope{event_type: event_type} = envelope) do
    case topic_for(event_type) do
      {:ok, topic} ->
        message = flatten(envelope)
        partition = select_partition(topic, envelope)

        case :brod.produce_sync(@client, topic, partition, "", Jason.encode!(message)) do
          :ok ->
            :ok

          {:error, reason} ->
            Logger.warning("Kafka publish failed",
              event_type: event_type,
              topic: topic,
              reason: inspect(reason)
            )

            {:error, reason}
        end

      :skip ->
        :ok
    end
  end

  # -- Private --

  defp topic_for(event_type) do
    case Enum.find(@topics, fn {prefix, _} -> String.starts_with?(event_type, prefix) end) do
      {_, topic} -> {:ok, topic}
      nil -> :skip
    end
  end

  defp select_partition(topic, %EventEnvelope{merchant_id: mid, aggregate_id: agg_id}) do
    key = mid || agg_id

    case :brod.get_partitions_count(@client, topic) do
      {:ok, count} -> rem(:erlang.phash2(key), count)
      _ -> 0
    end
  end

  defp flatten(%EventEnvelope{} = envelope) do
    EventEnvelope.to_map(envelope)
    |> Map.delete("payload")
    |> Map.merge(envelope.payload)
  end
end
