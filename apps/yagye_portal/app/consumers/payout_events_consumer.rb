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
    evt = Acl::CorePayoutEvent.new(payload)
    return unless evt.valid?

    existing = PortalPayout.find_by(payout_code: evt.payout_code)
    return if existing&.last_event_id == evt.event_id && evt.event_id.present?

    attrs = {
      payout_code:             evt.payout_code,
      merchant_code:           evt.merchant_code,
      mode:                    evt.mode,
      aggregate_version:       evt.aggregate_version,
      state:                   evt.state,
      amount:                  evt.amount,
      currency:                evt.currency,
      destination_type:        evt.destination_type,
      destination_fingerprint: evt.destination_fingerprint,
      scheduled_for:           evt.scheduled_for,
      failure_code:            evt.failure_code,
      last_event_id:           evt.event_id,
      last_applied_at:         evt.last_applied_at
    }.compact

    PortalPayout.upsert(attrs, unique_by: :payout_code, update_only: attrs.keys - [ :payout_code ])
  end
end
