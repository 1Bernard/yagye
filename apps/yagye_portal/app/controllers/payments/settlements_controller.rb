# frozen_string_literal: true

module Payments
  class SettlementsController < ApplicationController
    def index
      authorize PortalSettlement, :index?
      scope = policy_scope(PortalSettlement)
      pagy, settlements = pagy(scope.order(last_applied_at: :desc), limit: 25)
      render Payments::Settlements::IndexView.new(
        settlements: settlements, pagy: pagy,
        state_filter: params[:state], query: params[:q],
        stats: settlement_stats(scope)
      )
    end

    def show
      settlement = decode_id(PortalSettlement)
      authorize settlement
      breaks = []
      if settlement.merchant_code.present?
        result = CoreApiClient.new.list_reconciliation_breaks(settlement.merchant_code)
        breaks = result.success? ? (result.body["data"] || []) : []
      end
      render Payments::Settlements::ShowView.new(settlement: settlement, breaks: breaks)
    end
    private

    def settlement_stats(scope)
      mtd_start = Time.current.beginning_of_month
      {
        settled_mtd: scope.where(state: "reconciled")
                          .where("period_end >= ?", mtd_start)
                          .sum(:expected_net),
        pending:     scope.where(state: %w[pending processing]).count,
        reconciled:  scope.where(state: "reconciled").count,
        disputed:    scope.where(state: "disputed").count
      }
    end
  end
end
