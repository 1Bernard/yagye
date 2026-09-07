defmodule YagyeCore.MerchantWebhooks.RabbitMQ.DeliveryPipeline do
  @moduledoc """
  Broadway pipeline consuming from `yagye.webhooks.delivery`.
  For each message:
    1. Decrypts the HMAC signing secret (AES-256-GCM via Vault).
    2. Signs the payload with HMAC-SHA256.
    3. POSTs to the merchant's endpoint URL (5s timeout, no redirects).
    4. Acks on 2xx; nacks on any other outcome (RabbitMQ requeues until DLX).
    5. Records the attempt in `merchant_webhook_deliveries`.
    6. Emits a `webhook.delivery.attempted` outbox event → Redpanda → Portal.
  """

  use Broadway

  require Logger

  alias YagyeCore.MerchantWebhooks.RabbitMQ.Topology
  alias YagyeCore.MerchantWebhooks.Schemas.{MerchantWebhookDelivery, MerchantWebhookEndpoint}
  alias YagyeCore.Outbox.Schemas.OutboxMessage
  alias YagyeCore.Repo
  alias YagyeCore.Shared.Vault

  @user_agent "Yagye-Webhook/1.0"
  @timeout_ms 5_000
  @max_response_body 4_096

  def start_link(_opts \\ []) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module: {BroadwayRabbitMQ.Producer, producer_opts()},
        concurrency: 1
      ],
      processors: [default: [concurrency: 10, min_demand: 1, max_demand: 5]],
      batchers: []
    )
  end

  @impl Broadway
  def handle_message(_processor, %Broadway.Message{data: raw} = message, _context) do
    case Jason.decode(raw) do
      {:ok, task} ->
        case deliver(task) do
          {:ok, _} -> message
          {:error, _} -> Broadway.Message.failed(message, :delivery_failed)
        end

      {:error, _} ->
        Broadway.Message.failed(message, :bad_json)
    end
  end

  @impl Broadway
  def handle_failed(messages, _context) do
    # Nack so RabbitMQ requeues; Broadway RabbitMQ handles nack automatically on failed messages.
    messages
  end

  # ── Delivery ─────────────────────────────────────────────────────────────────

  defp deliver(task) do
    endpoint_id = task["endpoint_id"]
    url = task["url"]
    secret_hex = task["secret_encrypted"]
    event_id = task["event_id"]
    event_type = task["event_type"]
    merchant_id = task["merchant_id"]
    merchant_code = task["merchant_code"]
    body_map = task["body"] || %{}
    attempt = task["attempt"] || 1

    secret_bin = Base.decode16!(secret_hex, case: :lower)
    signing_secret = Vault.decrypt(secret_bin)

    payload_json = Jason.encode!(body_map)
    signature = sign(payload_json, signing_secret)
    delivery_id = Uniq.UUID.uuid7()
    timestamp = DateTime.utc_now()

    headers = %{
      "Content-Type" => "application/json",
      "User-Agent" => @user_agent,
      "X-Yagye-Signature" => "sha256=#{signature}",
      "X-Yagye-Delivery" => delivery_id,
      "X-Yagye-Event" => event_type,
      "X-Yagye-Timestamp" => DateTime.to_unix(timestamp) |> to_string()
    }

    {duration_ms, result} =
      :timer.tc(fn ->
        Req.post(url,
          body: payload_json,
          headers: headers,
          receive_timeout: @timeout_ms,
          redirect: false
        )
      end)

    duration_ms = div(duration_ms, 1_000)

    {state, response_status, response_body} =
      case result do
        {:ok, %{status: status, body: body}} when status in 200..299 ->
          {"delivered", status, truncate(body)}

        {:ok, %{status: status, body: body}} ->
          {"failed", status, truncate(body)}

        {:error, reason} ->
          {"failed", nil, inspect(reason)}
      end

    record_delivery(%{
      endpoint_id: endpoint_id,
      event_id: event_id,
      event_type: event_type,
      attempt: attempt,
      state: state,
      request_headers: headers,
      request_body: body_map,
      response_status: response_status,
      response_body: response_body,
      duration_ms: duration_ms,
      delivered_at: if(state == "delivered", do: timestamp)
    })

    emit_outbox_event(%{
      merchant_id: merchant_id,
      merchant_code: merchant_code,
      endpoint_id: endpoint_id,
      delivery_id: delivery_id,
      event_id: event_id,
      event_type: event_type,
      attempt: attempt,
      state: state,
      response_status: response_status,
      duration_ms: duration_ms,
      delivered_at: if(state == "delivered", do: DateTime.to_iso8601(timestamp))
    })

    if state == "failed" do
      {:error, response_status}
    else
      update_endpoint_failures(endpoint_id, state)
      {:ok, :delivered}
    end
  end

  defp record_delivery(attrs) do
    %MerchantWebhookDelivery{}
    |> MerchantWebhookDelivery.changeset(attrs)
    |> Repo.insert(
      on_conflict:
        {:replace,
         [:state, :response_status, :response_body, :duration_ms, :delivered_at, :updated_at]},
      conflict_target: [:endpoint_id, :event_id, :attempt]
    )
  end

  defp emit_outbox_event(delivery_attrs) do
    # Emit to `yagye.webhooks.v1` Redpanda topic via outbox.
    # We don't have a schema struct here, so we use a bare outbox insert.
    msg_attrs = %{
      event_id: Uniq.UUID.uuid7(),
      aggregate_type: "webhook_delivery",
      aggregate_id: delivery_attrs.delivery_id,
      aggregate_version: 1,
      event_type: "webhook.delivery.attempted",
      event_version: 1,
      partition_key: delivery_attrs.merchant_id,
      merchant_id: delivery_attrs.merchant_id,
      destination: "kafka:yagye.webhooks.v1",
      envelope: %{
        "event_id" => Uniq.UUID.uuid7(),
        "event_type" => "webhook.delivery.attempted",
        "event_version" => 1,
        "aggregate_type" => "webhook_delivery",
        "aggregate_id" => delivery_attrs[:delivery_id],
        "aggregate_version" => 1,
        "merchant_id" => delivery_attrs.merchant_id,
        "mode" => "live",
        "occurred_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "payload" => %{
          "delivery_id" => delivery_attrs[:delivery_id],
          "endpoint_id" => delivery_attrs.endpoint_id,
          "merchant_code" => delivery_attrs.merchant_code,
          "event_id" => delivery_attrs.event_id,
          "webhook_event_type" => delivery_attrs.event_type,
          "attempt" => delivery_attrs.attempt,
          "state" => delivery_attrs.state,
          "response_status" => delivery_attrs.response_status,
          "duration_ms" => delivery_attrs.duration_ms,
          "delivered_at" => delivery_attrs[:delivered_at]
        }
      },
      mode: "live",
      occurred_at: DateTime.utc_now()
    }

    OutboxMessage.changeset(
      %OutboxMessage{},
      msg_attrs
    )
    |> Repo.insert()
  end

  defp update_endpoint_failures(endpoint_id, "delivered") do
    case Repo.get(MerchantWebhookEndpoint, endpoint_id) do
      nil -> :ok
      ep -> ep |> MerchantWebhookEndpoint.record_success_changeset() |> Repo.update()
    end
  end

  defp update_endpoint_failures(endpoint_id, "failed") do
    case Repo.get(MerchantWebhookEndpoint, endpoint_id) do
      nil ->
        :ok

      ep ->
        if ep.consecutive_failures + 1 >= 50 do
          ep |> MerchantWebhookEndpoint.disable_changeset() |> Repo.update()
        else
          ep |> MerchantWebhookEndpoint.record_failure_changeset() |> Repo.update()
        end
    end
  end

  defp sign(payload, secret) do
    :crypto.mac(:hmac, :sha256, secret, payload) |> Base.encode16(case: :lower)
  end

  defp truncate(body) when is_binary(body), do: String.slice(body, 0, @max_response_body)
  defp truncate(body), do: inspect(body) |> String.slice(0, @max_response_body)

  defp producer_opts do
    [
      queue: Topology.queue(),
      connection:
        Application.get_env(:yagye_core, :rabbitmq_url, "amqp://guest:guest@localhost:5672"),
      qos: [prefetch_count: 20],
      on_failure: :reject_and_requeue
    ]
  end
end
