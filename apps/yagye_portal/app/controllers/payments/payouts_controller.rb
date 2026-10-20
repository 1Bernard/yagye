# frozen_string_literal: true

module Payments
  class PayoutsController < ApplicationController
    def index
      authorize PortalPayout, :index?
      filtered = ::Payouts::PayoutsQuery.new(policy_scope(PortalPayout)).call(
        state: params[:state], from: params[:from], to: params[:to]
      )
      pagy, payouts = pagy(filtered, limit: 25)
      render Payments::Payouts::IndexView.new(
        payouts:                payouts,
        pagy:                   pagy,
        state_filter:           params[:state],
        query:                  params[:q],
        from:                   params[:from],
        to:                     params[:to],
        view:                   params[:view].presence_in(%w[list grid]) || "list",
        stats:                  payout_stats(policy_scope(PortalPayout)),
        pending_requests_count: pending_requests_count
      )
    end

    def filter
      authorize PortalPayout, :index?
      render Payments::Payouts::FilterView.new(
        state: params[:state],
        query: params[:q],
        from:  params[:from],
        to:    params[:to]
      )
    end

    def show
      payout = find_owned!(PortalPayout)
      authorize payout
      render Payments::Payouts::ShowView.new(payout: payout)
    end

    def statement
      authorize PortalPayout, :index?
      payout = find_owned!(PortalPayout)
      render Payments::Payouts::StatementView.new(payout: payout), layout: false
    end

    private

    def payout_stats(scope)
      merchant_code = current_user.internal_staff? ? nil : current_user.merchant_code
      ::Payouts::PayoutStatsQuery.new(scope, merchant_code: merchant_code).call
    end

    def pending_requests_count
      base = PortalPayoutRequest.pending_review
      base = base.for_merchant(current_user.merchant_code) unless current_user.internal_staff?
      base.count
    end
  end
end
