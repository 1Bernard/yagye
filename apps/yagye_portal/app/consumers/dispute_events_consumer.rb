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
      Notifications::DeliveryService.schedule(
        merchant_code:   event.merchant_code,
        event_type:      "dispute_opened",
        title:           "New dispute opened",
        body:            "#{format_minor_units(event.amount, event.currency)} · Ref: #{event.reference}",
        link:            "/disputes",
        metadata:        { core_dispute_id: event.core_dispute_id, reference: event.reference },
        mode:            "live",
        urgency:         "critical",
        source_event_id: event.event_id.presence && "#{event.event_id}:dispute_opened"
      )
    when "resolved", "won", "lost"
      Notifications::DeliveryService.schedule(
        merchant_code:   event.merchant_code,
        event_type:      "dispute_resolved",
        title:           "Dispute resolved",
        body:            "Ref: #{event.reference} — #{event.status}",
        link:            "/disputes",
        metadata:        { core_dispute_id: event.core_dispute_id, reference: event.reference },
        mode:            "live",
        urgency:         "info",
        source_event_id: event.event_id.presence && "#{event.event_id}:dispute_resolved"
      )
    end
  rescue StandardError => e
    Rails.logger.warn("[DisputeEventsConsumer] notify failed: #{e.message}")
  end

  def format_minor_units(minor_units, currency_code = "GHS")
    return "—" if minor_units.nil?
    n = minor_units.to_f / 100
    whole, frac = sprintf("%.2f", n).split(".")
    "#{currency_code} #{whole.to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\1,').reverse}.#{frac}"
  end
end
