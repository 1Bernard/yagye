# frozen_string_literal: true

# Consumes api_key.* events from Core and keeps portal_api_keys in sync.
# Topic:   yagye.api_keys.v1
# Pattern: idempotent upsert keyed on key_id + last_event_id guard
class ApiKeyEventsConsumer < ApplicationConsumer
  def consume
    messages.each do |message|
      upsert(message.payload)
    rescue StandardError => e
      Rails.logger.error("ApiKeyEventsConsumer: failed — #{e.message}")
    end
  end

  private

  def upsert(payload)
    evt = Acl::CoreApiKeyEvent.new(payload)
    return unless evt.valid?

    existing = PortalApiKey.find_by(key_id: evt.key_id)
    return if existing&.last_event_id == evt.event_id && evt.event_id.present?

    attrs = {
      key_id:          evt.key_id,
      merchant_code:   evt.merchant_code,
      label:           evt.label,
      key_prefix:      evt.key_prefix,
      kind:            evt.kind,
      mode:            evt.mode,
      scopes:          evt.scopes,
      created_by:      evt.created_by,
      expires_at:      evt.expires_at,
      last_used_at:    evt.last_used_at,
      revoked_at:      evt.revoked_at,
      last_event_id:   evt.event_id,
      last_applied_at: Time.current
    }.compact

    PortalApiKey.upsert(attrs, unique_by: :key_id,
                                update_only: attrs.keys - [ :key_id ])

    notify_key_created(evt) if evt.newly_created? && existing.nil?
  end

  def notify_key_created(evt)
    return if evt.merchant_code.blank?

    body = evt.key_prefix.present? ? "#{evt.label} (#{evt.key_prefix}...)" : evt.label

    Notifications::DeliveryService.schedule(
      merchant_code:   evt.merchant_code,
      event_type:      "api_key_created",
      title:           "New API key generated",
      body:            body,
      link:            "/developers",
      metadata:        { key_id: evt.key_id },
      mode:            evt.mode,
      urgency:         "info",
      source_event_id: evt.event_id.presence && "#{evt.event_id}:api_key_created"
    )
  rescue StandardError => e
    Rails.logger.warn("[ApiKeyEventsConsumer] notify failed: #{e.message}")
  end
end
