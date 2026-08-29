class Payment < ApplicationRecord
  self.table_name = "portal_payments"

  STATUSES = %w[initiated processing paid failed refunded disputed].freeze
  PROVIDERS = {
    "mtn_momo" => "MTN MoMo",
    "stripe" => "Stripe",
    "flutterwave" => "Flutterwave",
    "paystack" => "Paystack"
  }.freeze

  scope :for_merchant, ->(code) { where(merchant_code: code) }
  scope :by_status,    ->(s)    { where(status: s) }
  scope :search_ref,   ->(q)    { where("reference ILIKE ? OR customer_msisdn LIKE ?", "%#{sanitize_sql_like(q)}%", "%#{sanitize_sql_like(q)}%") }
  scope :recent,               -> { order(created_at: :desc) }

  def masked_msisdn
    return "—" unless customer_msisdn.present?

    customer_msisdn.gsub(/(\d{3})\d{3}(\d+)/, '\1 *** \2')
  end

  def formatted_amount
    major = amount_cents / 100.0
    format("%s %.2f", currency, major)
  end

  def provider_label
    PROVIDERS.fetch(provider.to_s, provider.to_s.humanize)
  end
end
