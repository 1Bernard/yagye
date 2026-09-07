# frozen_string_literal: true

class DisputeEventsConsumer < ApplicationConsumer
  def consume
    messages.each do |message|
      event = Acl::CoreDisputeEvent.new(message.payload)
      next unless event.valid?
      upsert_dispute(event)
    end
  end

  private

  def upsert_dispute(event)
    attrs = {
      core_dispute_id:   event.core_dispute_id,
      merchant_code:     event.merchant_code,
      reference:         event.reference,
      core_payment_id:   event.core_payment_id,
      payment_reference: event.payment_reference,
      amount:            event.amount,
      currency:          event.currency,
      reason:            event.reason,
      status:            event.status,
      customer_msisdn:   event.customer_msisdn,
      network_deadline:  event.network_deadline,
      opened_at:         event.opened_at,
      resolved_at:       event.resolved_at,
      last_event_id:     event.event_id,
      last_applied_at:   Time.current
    }

    Dispute.upsert(attrs, unique_by: :core_dispute_id,
                          update_only: attrs.keys - %i[core_dispute_id])
  end
end
