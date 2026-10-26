# frozen_string_literal: true

module Payments
  class TransactionStatsQuery
    def initialize(scope)
      @scope = scope
    end

    def call
      mtd_start = Time.current.beginning_of_month
      ever_paid_mtd = @scope.where(status: %w[paid refunded]).where("paid_at >= ?", mtd_start)
      {
        volume_mtd:       ever_paid_mtd.sum(:amount),
        volume_currency:  @scope.pick(:currency) || "GHS",
        transactions_mtd: ever_paid_mtd.count,
        pending:          @scope.where(status: %w[created processing requires_action]).count,
        failed:           @scope.where(status: %w[failed cancelled]).count
      }
    end
  end
end
