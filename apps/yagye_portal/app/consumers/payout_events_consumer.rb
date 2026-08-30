# frozen_string_literal: true

class PayoutEventsConsumer < ApplicationConsumer
  def consume
    messages.each do |message|
      upsert(message.payload)
    rescue StandardError => e
      Rails.logger.error("PayoutEventsConsumer: #{e.message}")
    end
  end

  private

  def upsert(payload)
    code = payload["payout_code"] || payload["public_id"]
    return unless code.present?

    event_id = payload["event_id"].to_s
    existing = PortalPayout.find_by(payout_code: code)
    return if existing&.last_event_id == event_id && event_id.present?

    attrs = {
      payout_code:             code,
      merchant_code:           payload["merchant_code"],
      mode:                    payload["mode"] || "test",
      aggregate_version:       payload["aggregate_version"].to_i,
      state:                   payload["state"],
      amount:                  payload["amount"].to_i,
      currency:                payload["currency"] || "GHS",
      destination_type:        payload["destination_type"],
      destination_fingerprint: payload["destination_fingerprint"],
      scheduled_for:           payload["scheduled_for"],
      failure_code:            payload["failure_code"],
      last_event_id:           event_id,
      last_applied_at:         payload["timestamp"] || Time.current
    }.compact

    PortalPayout.upsert(attrs, unique_by: :payout_code, update_only: attrs.keys - [ :payout_code ])
  end
end
