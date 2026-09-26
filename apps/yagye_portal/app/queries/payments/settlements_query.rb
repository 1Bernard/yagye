# frozen_string_literal: true

module Payments
  class SettlementsQuery
    def self.with_merchant_name(relation = PortalSettlement.all)
      relation
        .joins("LEFT JOIN portal_merchants ON portal_merchants.merchant_code = portal_settlements.merchant_code")
        .select("portal_settlements.*, COALESCE(NULLIF(portal_merchants.trading_name, ''), portal_settlements.merchant_code) AS merchant_name")
    end

    def initialize(relation = PortalSettlement.all)
      @relation = relation
    end

    def call(filters = {})
      scoped = @relation
      scoped = scoped.where(portal_settlements: { state: filters[:state] }) if filters[:state].present?
      scoped = scoped.where("portal_settlements.value_date >= ?", filters[:from]) if filters[:from].present?
      scoped = scoped.where("portal_settlements.value_date <= ?", filters[:to])   if filters[:to].present?
      scoped.order("portal_settlements.last_applied_at DESC")
    end
  end
end
