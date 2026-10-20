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
    evt = Acl::CoreWebhookEvent.new(payload)

    if evt.deregister?
      delete_endpoint(evt)
    elsif evt.endpoint_event?
      upsert_endpoint(evt)
    elsif evt.delivery_event?
      upsert_delivery(evt)
    end
  end

  def upsert_endpoint(evt)
    return unless evt.endpoint_valid?

    attrs = {
      endpoint_id:          evt.endpoint_id,
      merchant_code:        evt.merchant_code,
      url:                  evt.url,
      mode:                 evt.mode,
      active:               evt.active,
      subscribed_events:    evt.subscribed_events,
      consecutive_failures: evt.consecutive_failures,
      last_event_id:        evt.last_event_id,
      last_applied_at:      Time.current,
      deleted_at:           nil
    }.compact

    PortalWebhookEndpoint.upsert(attrs, unique_by: :endpoint_id,
                                        update_only: attrs.keys - [ :endpoint_id ])
  end

  def delete_endpoint(evt)
    return unless evt.endpoint_valid?

    PortalWebhookEndpoint.find_by(endpoint_id: evt.endpoint_id)&.soft_delete!
  end

  def upsert_delivery(evt)
    return unless evt.delivery_valid?

    attrs = {
      delivery_id:     evt.delivery_id,
      endpoint_id:     evt.endpoint_id,
      merchant_code:   evt.merchant_code,
      event_type:      evt.delivery_event_type,
      event_id:        evt.delivery_event_id,
      state:           evt.state,
      attempt:         evt.attempt,
      response_status: evt.response_status,
      response_body:   evt.response_body,
      request_body:    evt.request_body,
      request_headers: evt.request_headers,
      duration_ms:     evt.duration_ms,
      delivered_at:    evt.delivered_at,
      last_applied_at: Time.current
    }.compact

    PortalWebhookDelivery.upsert(attrs, unique_by: :delivery_id,
                                        update_only: attrs.keys - [ :delivery_id ])
  end
end
