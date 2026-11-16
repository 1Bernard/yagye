# frozen_string_literal: true

class ReceiptMailer < ApplicationMailer
  # Accepts a plain hash of serializable values so this can be called via deliver_later.
  def payment_confirmed(to:, amount:, currency:, public_id:, merchant_name:, method:, network: nil, paid_at: "")
    @amount        = format("%.2f", amount / 100.0)
    @currency      = currency.presence || "GHS"
    @public_id     = public_id
    @merchant_name = merchant_name
    @method        = method.to_s.split("_").map(&:capitalize).join(" ")
    @network       = network&.upcase
    @paid_at       = paid_at.present? ? Time.parse(paid_at.to_s).strftime("%d %b %Y, %H:%M") : ""
    @receipt_url   = "#{ENV.fetch('RECEIPT_BASE_URL', 'https://app.yagye.io')}/r/#{public_id}"

    mail(
      to:      to,
      subject: "Payment confirmed – #{@currency} #{@amount}"
    )
  end
end
