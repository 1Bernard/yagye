class PaymentEventsConsumer < ApplicationConsumer
  def consume
    messages.each do |message|
      upsert_payment(message.payload)
    rescue StandardError => e
      Rails.logger.error("PaymentEventsConsumer: failed to process message — #{e.message}")
    end
  end

  private

  def upsert_payment(payload)
    Payment.find_or_initialize_by(core_payment_id: payload["public_id"]).tap do |p|
      p.merchant_code   = payload["merchant_code"]
      p.reference       = payload["reference"]
      p.customer_msisdn = payload["customer_msisdn"]
      p.customer_email  = payload["customer_email"]
      p.amount_cents    = payload["amount_cents"]
      p.currency        = payload["currency"] || "GHS"
      p.status          = payload["status"]
      p.provider        = payload["provider"]
      p.payment_method  = payload["payment_method"]
      p.description     = payload["description"]
      p.metadata        = payload["metadata"] || {}
      p.paid_at         = payload["paid_at"]
      p.settled_at      = payload["settled_at"]
      p.save!
    end
  end
end
