# frozen_string_literal: true

module Payouts
  # Returns the next in-flight payout for a merchant, or an aggregate summary
  # for ops staff. Returns nil when nothing is scheduled.
  class UpcomingPayoutQuery
    def initialize(relation = PortalPayout.all, is_ops: false)
      @relation = relation
      @is_ops   = is_ops
    end

    def call
      scoped = @relation
      scoped = scoped.where(mode: Current.mode) if Current.mode.present?

      in_flight = scoped
                    .in_flight
                    .where("scheduled_for >= ?", Date.today)
                    .order(scheduled_for: :asc)

      @is_ops ? build_ops_summary(in_flight) : build_merchant_summary(in_flight)
    end

    private

    def build_merchant_summary(relation)
      next_payout = relation.first
      return nil unless next_payout

      days = (next_payout.scheduled_for - Date.today).to_i
      {
        kind:       :merchant,
        amount:     next_payout.amount,
        currency:   next_payout.currency,
        date:       next_payout.scheduled_for,
        state:      next_payout.state,
        days_until: days
      }
    end

    def build_ops_summary(relation)
      count = relation.count
      return nil if count.zero?

      total    = relation.sum(:amount)
      next_one = relation.first

      {
        kind:       :ops,
        count:      count,
        total:      total,
        currency:   next_one.currency,
        next_date:  next_one.scheduled_for,
        days_until: (next_one.scheduled_for - Date.today).to_i
      }
    end
  end
end
