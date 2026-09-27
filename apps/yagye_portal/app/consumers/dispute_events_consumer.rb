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
    notify_dispute(event)
  end

  def notify_dispute(event)
    case event.status
    when "open"
      Notifications::DeliveryService.deliver(
        merchant_code: event.merchant_code,
        event_type:    "dispute_opened",
        title:         "New dispute opened",
        body:          "#{event.currency} #{sprintf('%.2f', event.amount.to_f / 100)} · Ref: #{event.reference}",
        link:          "/disputes",
        metadata:      { core_dispute_id: event.core_dispute_id, reference: event.reference }
      )
    when "resolved", "won", "lost"
      Notifications::DeliveryService.deliver(
        merchant_code: event.merchant_code,
        event_type:    "dispute_resolved",
        title:         "Dispute resolved",
        body:          "Ref: #{event.reference} — #{event.status}",
        link:          "/disputes",
        metadata:      { core_dispute_id: event.core_dispute_id, reference: event.reference }
      )
    end
  rescue StandardError => e
    Rails.logger.warn("[DisputeEventsConsumer] notify failed: #{e.message}")
  end
end
