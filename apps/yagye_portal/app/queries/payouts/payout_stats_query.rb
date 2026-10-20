# frozen_string_literal: true

module Payouts
  # Aggregates payout index stats: MTD paid volume, failed count, and pending settlement summary.
  # merchant_code: nil means ops (all merchants).
  class PayoutStatsQuery
    def initialize(payout_scope, merchant_code:)
      @scope         = payout_scope
      @merchant_code = merchant_code
    end

    def call
      now = Time.current

      paid_mtd   = @scope.where(state: "paid")
                         .where("last_applied_at >= ?", now.beginning_of_month)
                         .sum(:amount)
      failed_30d = @scope.where(state: "failed")
                         .where("last_applied_at >= ?", 30.days.ago)
                         .count
      currency   = @scope.where(state: "paid").pick(:currency) || "GHS"

      settlement = PendingSettlementQuery.new(@merchant_code).call

      {
        paid_mtd:        paid_mtd,
        currency:        currency,
        unsettled:       settlement[:amount],
        next_value_date: settlement[:next_value_date],
        failed_30d:      failed_30d
      }
    end
  end
end
