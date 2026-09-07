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
      paid_at:         event.paid_at,
      settled_at:      event.settled_at,
      mode:            event.mode
    }.compact

    Payment.find_or_initialize_by(core_payment_id: event.public_id).tap do |p|
      p.assign_attributes(attrs)
      p.save!
    end
  end
end
