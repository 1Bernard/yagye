defmodule YagyeCore.MerchantWebhooks.Workers.WebhookDispatchWorker do
  @moduledoc """
  Oban worker: for a published domain event, fan-out to matching merchant
  webhook endpoints via RabbitMQ.

  Enqueued by the OutboxRelayWorker for every event type that merchants can
  subscribe to (payment.*, dispute.*, refund.*).
  """

  use Oban.Worker, queue: :webhooks, max_attempts: 3, unique: [period: 30]

  alias YagyeCore.Merchants
  alias YagyeCore.MerchantWebhooks
  alias YagyeCore.Outbox.EventEnvelope

  # Internal Core event types → merchant-facing API event names.
  # Merchants subscribe and receive using these names;
  # Core uses state-machine names internally.
  @event_type_map %{
    "payment.succeeded" => "payment.paid",
    "payment.refunded" => "payment.refunded",
    "payment.failed" => "payment.failed",
    "payment.disputed" => "payment.disputed",
    "dispute.opened" => "dispute.opened",
    "dispute.evidence_submitted" => "dispute.evidence_submitted",
    "dispute.resolved" => "dispute.resolved",
    "refund.created" => "refund.created",
    "refund.failed" => "refund.failed",
    "merchant.kyb.approved" => "merchant.kyb.approved",
    "merchant.kyb.rejected" => "merchant.kyb.rejected"
  }

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"outbox_id" => _outbox_id, "envelope" => raw_envelope}}) do
    envelope = EventEnvelope.from_map(raw_envelope)

    merchant_id = envelope.merchant_id
    merchant_code = merchant_code_for(merchant_id)
    merchant_event_type = Map.get(@event_type_map, envelope.event_type, envelope.event_type)

    MerchantWebhooks.dispatch_event(
      merchant_id,
      merchant_code,
      merchant_event_type,
      envelope.event_id,
      envelope.mode,
      envelope.payload
    )
  end

  defp merchant_code_for(nil), do: nil

  defp merchant_code_for(merchant_id) do
    case Merchants.get_merchant_by_id(merchant_id) do
      {:ok, merchant} -> merchant.public_id
      _ -> nil
    end
  end
end
