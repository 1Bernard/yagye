defmodule YagyeCore.MerchantWebhooks.RabbitMQ.Publisher do
  @moduledoc """
  Publishes a webhook delivery task to the RabbitMQ exchange.
  Each task represents one delivery attempt for one endpoint + one event.
  """

  alias YagyeCore.MerchantWebhooks.RabbitMQ.{Connection, Topology}

  @doc """
  Enqueues a delivery task. Returns :ok or {:error, reason}.

  payload fields consumed by the Broadway processor:
    endpoint_id, url, secret_encrypted (hex), event_id, event_type,
    merchant_id, merchant_code, body (the event payload map)
  """
  def publish(task) when is_map(task) do
    with {:ok, conn} <- Connection.get(),
         {:ok, chan} <- AMQP.Channel.open(conn) do
      encoded = Jason.encode!(task)

      result =
        AMQP.Basic.publish(
          chan,
          Topology.exchange(),
          Topology.routing_key(),
          encoded,
          content_type: "application/json",
          persistent: true
        )

      AMQP.Channel.close(chan)
      result
    end
  end
end
