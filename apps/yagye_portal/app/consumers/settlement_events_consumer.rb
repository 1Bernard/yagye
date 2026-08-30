# frozen_string_literal: true

class SettlementEventsConsumer < ApplicationConsumer
  def consume
    messages.each do |message|
      upsert(message.payload)
    rescue StandardError => e
      Rails.logger.error("SettlementEventsConsumer: #{e.message}")
    end
  end

  private

  def upsert(payload)
    code = payload["settlement_code"]
    return unless code.present?

    event_id = payload["event_id"].to_s
    existing = PortalSettlement.find_by(settlement_code: code)
    return if existing&.last_event_id == event_id && event_id.present?

    attrs = {
      settlement_code:   code,
      merchant_code:     payload["merchant_code"],
      provider_code:     payload["provider_code"],
      mode:              payload["mode"] || "test",
      aggregate_version: payload["aggregate_version"].to_i,
      state:             payload["state"],
      currency:          payload["currency"] || "GHS",
      period_start:      payload["period_start"],
      period_end:        payload["period_end"],
      expected_net:      payload["expected_net"].to_i,
      reported_net:      payload["reported_net"],
      variance:          payload["variance"],
      value_date:        payload["value_date"],
      item_count:        payload["item_count"],
      last_event_id:     event_id,
      last_applied_at:   payload["timestamp"] || Time.current
    }.compact

    PortalSettlement.upsert(attrs, unique_by: :settlement_code, update_only: attrs.keys - [ :settlement_code ])
  end
end
