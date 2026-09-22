defmodule YagyeCore.MerchantWebhooks.RabbitMQ.DeliveryPipeline do
  @moduledoc """
  Broadway pipeline consuming from `yagye.webhooks.delivery`.
  For each message:
    1. Decrypts the HMAC signing secret (AES-256-GCM via Vault).
    2. Signs the payload with HMAC-SHA256.
    3. POSTs to the merchant's endpoint URL (5s timeout, no redirects).
    4. Always acks the RabbitMQ message (never requeues).
    5. Records the attempt in `merchant_webhook_deliveries`.
    6. Emits a `webhook.delivery.attempted` outbox event → Redpanda → Portal.
    7. On failure, schedules WebhookDeliveryRetryWorker via Oban with exponential
       backoff (10s → 60s → 10m → 1h). Stops after @max_attempts total.
  """

  use Broadway

  require Logger

  alias YagyeCore.MerchantWebhooks.RabbitMQ.Topology
  alias YagyeCore.MerchantWebhooks.Schemas.{MerchantWebhookDelivery, MerchantWebhookEndpoint}
  alias YagyeCore.MerchantWebhooks.Workers.WebhookDeliveryRetryWorker
  alias YagyeCore.Outbox.Schemas.OutboxMessage
  alias YagyeCore.Repo
  alias YagyeCore.Shared.Vault

  @user_agent "Yagye-Webhook/1.0"
  @timeout_ms 5_000
  @max_response_body 4_096
  @max_attempts 5
  # Seconds to wait before each retry attempt (index 0 = delay before attempt 2, etc.)
  @retry_delays [10, 60, 600, 3_600]

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
      {:ok, task} -> deliver(task)
      {:error, _} -> Logger.warning("WebhookDeliveryPipeline: dropped malformed JSON message")
    end

    # Always ack — retries are driven by Oban with exponential backoff,
    # not by RabbitMQ requeue. This prevents the tight retry loop.
    message
  end

  # ── Delivery ─────────────────────────────────────────────────────────────────

  defp deliver(task) do
    endpoint_id = task["endpoint_id"]
    # Public ID is the Portal-facing identifier; fall back to endpoint_id for old tasks.
    endpoint_public_id = task["endpoint_public_id"] || endpoint_id
    url = task["url"]
    secret_hex = task["secret_encrypted"]
    event_id = task["event_id"]
    event_type = task["event_type"]
    merchant_id = task["merchant_id"]
    merchant_code = task["merchant_code"]
    body_map = task["body"] || %{}
    attempt = task["attempt"] || 1

    secret_bin = Base.decode16!(secret_hex, case: :lower)
    {:ok, signing_secret} = Vault.decrypt(secret_bin)

    # Wrap the raw domain payload in a stable event envelope that merchants parse.
    # `event_type` is already the merchant-facing name (e.g. "payment.paid"),
    # translated by WebhookDispatchWorker before it reaches RabbitMQ.
    livemode = Map.get(body_map, "mode") == "live"
    data_object = build_data_object(body_map)

    envelope_body = %{
      "id" => "evt_#{Uniq.UUID.uuid7()}",
      "object" => "event",
      "event" => event_type,
      "created_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "livemode" => livemode,
      "data" => %{"object" => data_object}
    }

    payload_json = Jason.encode!(envelope_body)
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

    {duration_ms, state, response_status, response_body} =
      execute_post(url, payload_json, headers)

    record_delivery(%{
      endpoint_id: endpoint_id,
      event_id: event_id,
      event_type: event_type,
      attempt: attempt,
      state: state,
      request_headers: headers,
      request_body: envelope_body,
      response_status: response_status,
      response_body: response_body,
      duration_ms: duration_ms,
      delivered_at: if(state == "delivered", do: timestamp)
    })

    emit_outbox_event(%{
      merchant_id: merchant_id,
      merchant_code: merchant_code,
      endpoint_id: endpoint_public_id,
      delivery_id: delivery_id,
      event_id: event_id,
      event_type: event_type,
      attempt: attempt,
      state: state,
      response_status: response_status,
      response_body: response_body,
      request_body: envelope_body,
      request_headers: headers,
      duration_ms: duration_ms,
      delivered_at: if(state == "delivered", do: DateTime.to_iso8601(timestamp))
    })

    update_endpoint_failures(endpoint_id, state)

    if state == "failed" do
      schedule_retry(task, attempt, endpoint_public_id)
    end

    :ok
  end

  defp execute_post(url, payload_json, headers) do
    {micros, result} =
      :timer.tc(fn ->
        Req.post(url,
          body: payload_json,
          headers: headers,
          receive_timeout: @timeout_ms,
          redirect: false
        )
      end)

    duration_ms = div(micros, 1_000)

    {state, response_status, response_body} =
      case result do
        {:ok, %{status: status, body: body}} when status in 200..299 ->
          {"delivered", status, truncate(body)}

        {:ok, %{status: status, body: body}} ->
          {"failed", status, truncate(body)}

        {:error, reason} ->
          {"failed", nil, inspect(reason)}
      end

    {duration_ms, state, response_status, response_body}
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
          "webhook_event_id" => delivery_attrs.event_id,
          "webhook_event_type" => delivery_attrs.event_type,
          "attempt" => delivery_attrs.attempt,
          "state" => delivery_attrs.state,
          "response_status" => delivery_attrs.response_status,
          "response_body" => delivery_attrs[:response_body],
          "request_body" => delivery_attrs[:request_body],
          "request_headers" => delivery_attrs[:request_headers],
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

  # No retry after the last attempt — delivery is permanently failed.
  defp schedule_retry(_task, attempt, _endpoint_public_id) when attempt >= @max_attempts, do: :ok

  defp schedule_retry(task, attempt, endpoint_public_id) do
    delay = Enum.at(@retry_delays, attempt - 1, 3_600)

    WebhookDeliveryRetryWorker.new(
      %{
        "endpoint_public_id" => endpoint_public_id,
        "event_id" => task["event_id"],
        "event_type" => task["event_type"],
        "merchant_id" => task["merchant_id"],
        "merchant_code" => task["merchant_code"],
        "body" => task["body"],
        "attempt" => attempt + 1
      },
      scheduled_at: DateTime.add(DateTime.utc_now(), delay, :second)
    )
    |> Oban.insert()
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

  # Maps the raw outbox payload to a clean, stable API-facing data object.
  # Internal field names (public_id, state) are renamed to their merchant-facing
  # equivalents (id, status). Only public fields are included.
  defp build_data_object(p) do
    status =
      case p["state"] do
        "succeeded" -> "paid"
        s -> s
      end

    %{
      "id" => p["public_id"],
      "object" => "payment",
      "status" => status,
      "amount" => p["amount"],
      "net_amount" => p["net_amount"],
      "currency" => p["currency"],
      "method" => p["method"],
      "provider" => p["provider"],
      "merchant_reference" => p["merchant_reference"],
      "checkout_session_id" => p["checkout_session_id"],
      "customer_email" => p["customer_email"],
      "customer_msisdn" => p["customer_msisdn"],
      "description" => p["description"],
      "paid_at" => p["paid_at"]
    }
    |> Map.reject(fn {_, v} -> is_nil(v) end)
  end

  defp truncate(body) when is_binary(body), do: String.slice(body, 0, @max_response_body)
  defp truncate(body), do: inspect(body) |> String.slice(0, @max_response_body)

  defp producer_opts do
    [
      queue: Topology.queue(),
      connection:
        Application.get_env(:yagye_core, :rabbitmq_url, "amqp://guest:guest@localhost:5672"),
      qos: [prefetch_count: 20],
      on_failure: :reject,
      declare: [
        durable: true,
        arguments: [{"x-dead-letter-exchange", :longstr, "yagye.webhooks.dead"}]
      ]
    ]
  end
end
