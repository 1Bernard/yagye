# frozen_string_literal: true

module Payments
  class SettlementsController < ApplicationController
    def index
      authorize PortalSettlement, :index?
      scope = policy_scope(PortalSettlement)
      pagy, settlements = pagy(scope.order(last_applied_at: :desc), limit: 25)
      render Payments::Settlements::IndexView.new(
        settlements: settlements, pagy: pagy,
        state_filter: params[:state], query: params[:q]
      )
    end

    def show
      settlement = decode_id(PortalSettlement)
      authorize settlement
      render Payments::Settlements::ShowView.new(settlement: settlement)
    end
  end
end
