# frozen_string_literal: true

# Consumes webhook.endpoint.* and webhook.delivery.* events from Core.
# Topic:   yagye.webhooks.v1
# Pattern: idempotent upsert on endpoint_id / delivery_id
class WebhookEventsConsumer < ApplicationConsumer
  def consume
    messages.each do |message|
      route(message.payload)
    rescue StandardError => e
      Rails.logger.error("WebhookEventsConsumer: failed — #{e.message}")
    end
  end

  private

  def route(payload)
    case payload["event_type"].to_s
    when /^webhook\.endpoint\./
      upsert_endpoint(payload)
    when /^webhook\.delivery\./
      upsert_delivery(payload)
    end
  end

  def upsert_endpoint(payload)
    endpoint_id = payload["endpoint_id"] || payload["public_id"]
    return unless endpoint_id.present?

    attrs = {
      endpoint_id:          endpoint_id,
      merchant_code:        payload["merchant_code"],
      url:                  payload["url"],
      mode:                 payload["mode"] || "test",
      active:               payload["active"] != false,
      subscribed_events:    Array(payload["subscribed_events"]),
      consecutive_failures: payload["consecutive_failures"].to_i,
      last_event_id:        payload["event_id"].to_s,
      last_applied_at:      Time.current
    }.compact

    PortalWebhookEndpoint.upsert(attrs, unique_by: :endpoint_id,
                                        update_only: attrs.keys - [ :endpoint_id ])
  end

  def upsert_delivery(payload)
    delivery_id = payload["delivery_id"] || payload["public_id"]
    return unless delivery_id.present?

    attrs = {
      delivery_id:     delivery_id,
      endpoint_id:     payload["endpoint_id"],
      merchant_code:   payload["merchant_code"],
      event_type:      payload["webhook_event_type"] || payload["event_type"],
      event_id:        payload["webhook_event_id"],
      state:           payload["state"] || "delivering",
      attempt:         payload["attempt"].to_i.then { |n| n > 0 ? n : 1 },
      response_status: payload["response_status"],
      response_body:   payload["response_body"],
      request_body:    payload["request_body"],
      request_headers: payload["request_headers"],
      duration_ms:     payload["duration_ms"],
      delivered_at:    payload["delivered_at"],
      last_applied_at: Time.current
    }.compact

    PortalWebhookDelivery.upsert(attrs, unique_by: :delivery_id,
                                        update_only: attrs.keys - [ :delivery_id ])
  end
end
