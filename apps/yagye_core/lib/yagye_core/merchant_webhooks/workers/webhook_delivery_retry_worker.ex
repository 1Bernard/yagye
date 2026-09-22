defmodule YagyeCore.MerchantWebhooks.Workers.WebhookDeliveryRetryWorker do
  @moduledoc false

  # Scheduled by DeliveryPipeline after a failed delivery attempt.
  # Fetches the endpoint's current URL from the DB (so URL updates take effect
  # on retry) and re-publishes a delivery task to RabbitMQ.
  #
  # Retry schedule (delays set by DeliveryPipeline.@retry_delays):
  #   Attempt 1 → immediate (Broadway, original RabbitMQ message)
  #   Attempt 2 → +10s
  #   Attempt 3 → +60s
  #   Attempt 4 → +10min
  #   Attempt 5 → +1h
  #   After attempt 5 → permanently failed, no more retries

  use Oban.Worker, queue: :webhooks, max_attempts: 1

  alias YagyeCore.MerchantWebhooks

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    endpoint_public_id = args["endpoint_public_id"]

    case MerchantWebhooks.get_endpoint_by_public_id(endpoint_public_id) do
      {:ok, endpoint} when endpoint.active ->
        task = %{
          "endpoint_id" => endpoint.id,
          "endpoint_public_id" => endpoint.public_id,
          "url" => endpoint.url,
          "secret_encrypted" => Base.encode16(endpoint.secret_encrypted, case: :lower),
          "event_id" => args["event_id"],
          "event_type" => args["event_type"],
          "merchant_id" => args["merchant_id"],
          "merchant_code" => args["merchant_code"],
          "body" => args["body"],
          "attempt" => args["attempt"]
        }

        MerchantWebhooks.publish_delivery_task(task)

      _ ->
        # Endpoint deleted or disabled — stop retrying.
        :ok
    end
  end
end
