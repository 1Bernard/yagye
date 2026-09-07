defmodule YagyeCore.MerchantWebhooks.RabbitMQ.Topology do
  @moduledoc """
  Declares the RabbitMQ exchange, delivery queue, and dead-letter queue at startup.

  Exchange:  `yagye.webhooks`  (direct)
  Queue:     `yagye.webhooks.delivery`  → where all delivery tasks land
  DLX:       `yagye.webhooks.dead`      (fanout)
  DLQ:       `yagye.webhooks.dead_letter`

  Per-merchant isolation is achieved via the message payload (not separate queues)
  to keep topology simple at P15 scale. P17+ can introduce per-merchant queues.
  """

  require Logger

  alias YagyeCore.MerchantWebhooks.RabbitMQ.Connection

  @exchange "yagye.webhooks"
  @dlx_exchange "yagye.webhooks.dead"
  @queue "yagye.webhooks.delivery"
  @dlq "yagye.webhooks.dead_letter"
  @routing_key "delivery"
  @max_attempts 5

  def setup! do
    with {:ok, conn} <- amqp_connection(),
         {:ok, chan} <- AMQP.Channel.open(conn) do
      declare_topology(chan)
      AMQP.Channel.close(chan)
      Logger.info("RabbitMQ topology declared")
    else
      {:error, reason} ->
        Logger.error("RabbitMQ topology setup failed", reason: inspect(reason))
        {:error, reason}
    end
  end

  defp declare_topology(chan) do
    # Dead-letter exchange and queue first
    :ok = AMQP.Exchange.declare(chan, @dlx_exchange, :fanout, durable: true)
    {:ok, _} = AMQP.Queue.declare(chan, @dlq, durable: true)
    :ok = AMQP.Queue.bind(chan, @dlq, @dlx_exchange)

    # Main exchange
    :ok = AMQP.Exchange.declare(chan, @exchange, :direct, durable: true)

    # Main delivery queue — messages DLX after max-redeliveries
    {:ok, _} =
      AMQP.Queue.declare(chan, @queue,
        durable: true,
        arguments: [
          {"x-dead-letter-exchange", :longstr, @dlx_exchange},
          {"x-delivery-limit", :long, @max_attempts}
        ]
      )

    :ok = AMQP.Queue.bind(chan, @queue, @exchange, routing_key: @routing_key)
  end

  defp amqp_connection do
    Connection.get()
  end

  def exchange, do: @exchange
  def queue, do: @queue
  def routing_key, do: @routing_key
end
