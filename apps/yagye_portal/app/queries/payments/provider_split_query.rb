# frozen_string_literal: true

module Payments
  class ProviderSplitQuery
    def initialize(relation = Payment.all)
      @relation = relation
    end

    def call(provider_code:, from: Time.current.beginning_of_month, limit: 10)
      @relation
        .joins("LEFT JOIN portal_merchants ON portal_merchants.merchant_code = portal_payments.merchant_code")
        .where(provider: provider_code, status: "paid")
        .where("portal_payments.paid_at >= ?", from)
        .group("portal_payments.merchant_code, COALESCE(NULLIF(portal_merchants.trading_name, ''), portal_payments.merchant_code)")
        .select(
          "COALESCE(NULLIF(portal_merchants.trading_name, ''), portal_payments.merchant_code) AS merchant_name",
          "portal_payments.merchant_code",
          "SUM(portal_payments.amount) AS total_volume",
          "COUNT(portal_payments.id) AS tx_count"
        )
        .order("SUM(portal_payments.amount) DESC")
        .limit(limit)
    end
  end
end
