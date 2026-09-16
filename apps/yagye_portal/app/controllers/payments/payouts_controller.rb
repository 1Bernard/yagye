# frozen_string_literal: true

module Payments
  class PayoutsController < ApplicationController
    def index
      authorize PortalPayout, :index?
      scope = policy_scope(PortalPayout)
      pagy, payouts = pagy(scope.order(last_applied_at: :desc), limit: 25)
      render Payments::Payouts::IndexView.new(
        payouts:      payouts,
        pagy:         pagy,
        state_filter: params[:state],
        query:        params[:q],
        stats:        payout_stats(scope)
      )
    end

    def show
      payout = decode_id(PortalPayout)
      authorize payout
      render Payments::Payouts::ShowView.new(payout: payout)
    end

    private

    def payout_stats(scope)
      now       = Time.current
      mtd_start = now.beginning_of_month

      paid_mtd   = scope.where(state: "paid")
                        .where("last_applied_at >= ?", mtd_start)
                        .sum(:amount)

      failed_30d = scope.where(state: "failed")
                        .where("last_applied_at >= ?", 30.days.ago)
                        .count

      currency   = scope.where(state: "paid").pick(:currency) || "GHS"

      # Unsettled balance and next settlement date from portal_settlements
      merchant_code  = current_user.internal_staff? ? nil : current_user.merchant_code
      settlement_scope = merchant_code \
        ? PortalSettlement.for_merchant(merchant_code) \
        : PortalSettlement.all
      pending_settlements = settlement_scope.where(state: %w[pending processing awaiting_approval])
      unsettled      = pending_settlements.sum(:expected_net)
      next_value_date = pending_settlements.where.not(value_date: nil)
                                           .minimum(:value_date)

      {
        paid_mtd:        paid_mtd,
        currency:        currency,
        unsettled:       unsettled,
        next_value_date: next_value_date,
        failed_30d:      failed_30d
      }
    end
  end
end
