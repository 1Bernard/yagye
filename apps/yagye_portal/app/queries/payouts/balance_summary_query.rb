# frozen_string_literal: true

module Payouts
  # Computes a merchant's accumulated payout balance — payments collected since
  # the last completed payout — and pairs it with the next scheduled payout date.
  #
  # "Balance" = sum of net_amount (falling back to amount) for paid payments
  # that post-date the last completed payout's scheduled_for. If no completed
  # payout exists the cycle start defaults to beginning of the current month.
  class BalanceSummaryQuery
    def initialize(payment_relation, payout_relation)
      @payment_relation = payment_relation
      @payout_relation  = payout_relation
    end

    def call
      if Current.mode.present?
        @payment_relation = @payment_relation.where(mode: Current.mode)
        @payout_relation  = @payout_relation.where(mode: Current.mode)
      end

      cycle_start   = last_completed_payout_date || Time.current.beginning_of_month
      next_payout   = next_scheduled_payout

      accumulated   = @payment_relation.where(status: "paid").where("paid_at >= ?", cycle_start)
      count         = accumulated.count
      return nil if count.zero? && next_payout.nil?

      gross         = accumulated.sum(:amount)
      net           = accumulated.sum("COALESCE(net_amount, amount - COALESCE(fee_amount, 0))")
      currency      = accumulated.pick(:currency) || "GHS"

      {
        balance:            net,
        gross:              gross,
        payment_count:      count,
        currency:           currency,
        cycle_start:        cycle_start,
        next_payout_date:   next_payout&.scheduled_for,
        next_payout_amount: next_payout&.amount,
        next_payout_state:  next_payout&.state
      }
    end

    private

    def last_completed_payout_date
      @payout_relation
        .where(state: "paid")
        .order(scheduled_for: :desc)
        .pick(:scheduled_for)
        &.beginning_of_day
    end

    def next_scheduled_payout
      @payout_relation
        .in_flight
        .where("scheduled_for >= ?", Date.today)
        .order(scheduled_for: :asc)
        .first
    end
  end
end
