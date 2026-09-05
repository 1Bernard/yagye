# frozen_string_literal: true

module Payments
  class PayoutsController < ApplicationController
    def index
      authorize PortalPayout, :index?
      scope = policy_scope(PortalPayout)
      pagy, payouts = pagy(scope.order(last_applied_at: :desc), limit: 25)
      render Payments::Payouts::IndexView.new(
        payouts: payouts, pagy: pagy,
        state_filter: params[:state], query: params[:q]
      )
    end

    def show
      payout = decode_id(PortalPayout)
      authorize payout
      render Payments::Payouts::ShowView.new(payout: payout)
    end
  end
end
