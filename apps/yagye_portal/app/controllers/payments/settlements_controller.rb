# frozen_string_literal: true

module Payments
  class SettlementsController < ApplicationController
    def index
      authorize PortalSettlement, :index?
      scope = policy_scope(PortalSettlement)
        .joins("LEFT JOIN portal_merchants ON portal_merchants.merchant_code = portal_settlements.merchant_code")
        .select("portal_settlements.*, COALESCE(NULLIF(portal_merchants.trading_name, ''), portal_settlements.merchant_code) AS merchant_name")
      scope = scope.where(portal_settlements: { state: params[:state] }) if params[:state].present?
      scope = scope.where("portal_settlements.value_date >= ?", params[:from]) if params[:from].present?
      scope = scope.where("portal_settlements.value_date <= ?", params[:to])   if params[:to].present?
      pagy, settlements = pagy(scope.order("portal_settlements.last_applied_at DESC"), limit: 25)
      core_result  = CoreApiClient.new.get_ops_settlement_dashboard
      ops_dashboard = core_result.success? ? core_result.body : {}
      render Payments::Settlements::IndexView.new(
        settlements:   settlements,
        pagy:          pagy,
        state_filter:  params[:state],
        query:         params[:q],
        from:          params[:from],
        to:            params[:to],
        stats:         settlement_stats(policy_scope(PortalSettlement)),
        ops_dashboard: ops_dashboard
      )
    end

    def filter
      authorize PortalSettlement, :index?
      render Payments::Settlements::FilterView.new(
        state: params[:state],
        query: params[:q],
        from:  params[:from],
        to:    params[:to]
      )
    end

    def show
      settlement = decode_id(PortalSettlement)
      authorize settlement
      merchant = PortalMerchant.find_by(merchant_code: settlement.merchant_code)
      breaks = []
      if settlement.merchant_code.present? && merchant
        result = CoreApiClient.new.list_reconciliation_breaks(settlement.merchant_code)
        breaks = result.success? ? (result.body["data"] || []) : []
      end
      render Payments::Settlements::ShowView.new(settlement: settlement, breaks: breaks, merchant: merchant)
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
