class Payment < ApplicationRecord
  self.table_name = "portal_payments"

  STATUSES = %w[created processing requires_action paid failed cancelled indeterminate refunded disputed].freeze
  PROVIDERS = {
    "mtn_momo"     => "MTN MoMo",
    "telecel_cash" => "Telecel Cash",
    "airteltigo"   => "AirtelTigo Money",
    "simulator"    => "Gateway Simulator"
  }.freeze

  scope :for_merchant, ->(code) { where(merchant_code: code) }
  scope :by_status,    ->(s)    { where(status: s) }
  scope :search_ref,   ->(q)    { where("reference ILIKE ? OR customer_msisdn LIKE ?", "%#{sanitize_sql_like(q)}%", "%#{sanitize_sql_like(q)}%") }
  scope :recent,               -> { order(created_at: :desc) }

  def masked_msisdn
    return nil unless customer_msisdn.present?

    customer_msisdn.gsub(/(\d{3})\d{3}(\d+)/, '\1 *** \2')
  end

  def customer_display
    customer_email.presence || masked_msisdn || "—"
  end

  def formatted_amount
    major = amount / 100.0
    format("%s %.2f", currency, major)
  end

  def provider_label
    PROVIDERS.fetch(provider.to_s, provider.to_s.humanize)
  end

  def method_label
    case payment_method
    when "mobile_money"  then provider_label
    when "card"          then "Card"
    when "bank_transfer" then "Bank Transfer"
    else payment_method&.humanize || "—"
    end
  end

  def method_icon
    case payment_method
    when "mobile_money"  then :phone
    when "card"          then :credit_card
    when "bank_transfer" then :bank
    else :layers
    end
  end
end
