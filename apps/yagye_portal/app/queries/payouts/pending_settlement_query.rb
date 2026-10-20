# frozen_string_literal: true

module Payouts
  # Summarises unsettled funds for a merchant (or all merchants when merchant_code is nil).
  # Returns { amount:, currency:, next_value_date: }.
  class PendingSettlementQuery
    PENDING_STATES = %w[pending processing awaiting_approval].freeze

    def initialize(merchant_code)
      @merchant_code = merchant_code
    end

    def call
      scope   = @merchant_code ? PortalSettlement.for_merchant(@merchant_code) : PortalSettlement.all
      pending = scope.where(state: PENDING_STATES)

      {
        amount:          pending.sum(:expected_net),
        currency:        pending.pick(:currency) || "GHS",
        next_value_date: pending.where.not(value_date: nil).minimum(:value_date)
      }
    end
  end
end
