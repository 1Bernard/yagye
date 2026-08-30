# frozen_string_literal: true

# Consumes dispute.* events from Core and keeps portal_disputes in sync.
# Topic:   yagye.portal.dispute_events
# Pattern: idempotent upsert keyed on core_dispute_id + last_event_id guard
class DisputeEventsConsumer < ApplicationConsumer
  def consume
    messages.each { |message| upsert(message.payload) }
  end

  private

  def upsert(payload)
    return unless payload["dispute_id"].present?

    attrs = {
      core_dispute_id:   payload["dispute_id"],
      merchant_code:     payload["merchant_code"],
      reference:         payload["reference"],
      core_payment_id:   payload["payment_id"],
      payment_reference: payload["payment_reference"],
      amount_cents:      payload["amount_cents"].to_i,
      currency:          payload["currency"] || "GHS",
      reason:            payload["reason"],
      status:            payload["status"],
      customer_msisdn:   payload["customer_msisdn"],
      network_deadline:  payload["network_deadline"],
      opened_at:         payload["opened_at"],
      resolved_at:       payload["resolved_at"],
      last_event_id:     payload["event_id"].to_s,
      last_applied_at:   Time.current
    }

    Dispute.upsert(attrs, unique_by: :core_dispute_id,
                          update_only: attrs.keys - %i[core_dispute_id])
  end
end
