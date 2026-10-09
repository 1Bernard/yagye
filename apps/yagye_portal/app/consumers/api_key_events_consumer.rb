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
    key_id = payload["key_id"] || payload["public_id"]
    return unless key_id.present?

    event_id = payload["event_id"].to_s
    existing = PortalApiKey.find_by(key_id: key_id)
    return if existing&.last_event_id == event_id && event_id.present?

    # Core stores mode as "sandbox"/"simulation"/"live"; Portal uses "test"/"live".
    portal_mode = case payload["mode"]
    when "sandbox", "simulation" then "test"
    when "live"                  then "live"
    else payload["mode"].presence || "test"
    end

    attrs = {
      key_id:        key_id,
      merchant_code: payload["merchant_code"],
      label:         payload["label"] || "",
      key_prefix:    payload["key_prefix"] || payload["prefix"] || "",
      kind:          payload["kind"] || "secret",
      mode:          portal_mode,
      scopes:        Array(payload["scopes"]),
      created_by:    payload["created_by"],
      expires_at:    payload["expires_at"],
      last_used_at:  payload["last_used_at"],
      revoked_at:    payload["revoked_at"],
      last_event_id: event_id,
      last_applied_at: Time.current
    }.compact

    PortalApiKey.upsert(attrs, unique_by: :key_id,
                                update_only: attrs.keys - [ :key_id ])

    if payload["revoked_at"].nil? && existing.nil?
      notify_key_created(payload)
    end
  end

  def notify_key_created(payload)
    merchant_code = payload["merchant_code"]
    return if merchant_code.blank?

    label  = payload["label"].presence || "API key"
    prefix = payload["key_prefix"] || payload["prefix"]
    body   = prefix.present? ? "#{label} (#{prefix}...)" : label

    Notifications::DeliveryService.deliver(
      merchant_code: merchant_code,
      event_type:    "api_key_created",
      title:         "New API key generated",
      body:          body,
      link:          "/developers",
      metadata:      { key_id: payload["key_id"] || payload["public_id"] }
    )
  rescue StandardError => e
    Rails.logger.warn("[ApiKeyEventsConsumer] notify failed: #{e.message}")
  end
end
