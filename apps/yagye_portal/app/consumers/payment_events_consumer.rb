# frozen_string_literal: true

class PaymentEventsConsumer < ApplicationConsumer
  def consume
    messages.each do |message|
      event = Acl::CorePaymentEvent.new(message.payload)
      next unless event.valid?
      upsert_payment(event)
    end
  end

  private

  def upsert_payment(event)
    attrs = {
      merchant_code:   event.merchant_code,
      reference:       event.reference,
      customer_msisdn: event.customer_msisdn,
      customer_email:  event.customer_email,
      amount:          event.amount.nonzero?,
      currency:        event.currency.presence,
      status:          event.status.presence,
      provider:        event.provider,
      payment_method:  event.payment_method,
      description:     event.description,
      metadata:        event.metadata,
      paid_at:                event.paid_at,
      settled_at:             event.settled_at,
      mode:                   event.mode,
      fee_amount:             event.fee_amount,
      net_amount:             event.net_amount,
      fulfilment_type:        event.fulfilment_type,
      shipping_country:       event.shipping_country,
      billing_shipping_match: event.billing_shipping_match
    }.compact

    Payment.find_or_initialize_by(core_payment_id: event.public_id).tap do |p|
      p.assign_attributes(attrs)
      p.save!
      broadcast_to_feed(p)
      broadcast_status_update(p)
    end
  end

  def broadcast_to_feed(payment)
    stream = "dashboard_feed_#{payment.merchant_code}_#{payment.mode}"
    html   = ApplicationController.render(
      Dashboard::FeedRowComponent.new(payment: payment),
      layout: false
    )
    Turbo::StreamsChannel.broadcast_prepend_to(
      stream,
      target: "payment-feed",
      html:   html
    )
  rescue StandardError => e
    Rails.logger.warn("[PaymentEventsConsumer] feed broadcast failed: #{e.message}")
  end

  def broadcast_status_update(payment)
    stream  = "payments_#{payment.merchant_code}_#{payment.mode}"
    target  = "payment-status-#{payment.id}"
    badge   = UI::StatusBadge.new(status: payment.status).call
    html    = "<div id=\"#{target}\">#{badge}</div>"
    Turbo::StreamsChannel.broadcast_replace_to(stream, target: target, html: html)
  rescue StandardError => e
    Rails.logger.warn("[PaymentEventsConsumer] status broadcast failed: #{e.message}")
  end
end
