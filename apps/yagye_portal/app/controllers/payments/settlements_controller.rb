# frozen_string_literal: true

module Payments
  class SettlementsController < ApplicationController
    def index
      authorize PortalSettlement, :index?
      base_scope = Payments::SettlementsQuery.with_merchant_name(policy_scope(PortalSettlement))
      filtered   = Payments::SettlementsQuery.new(base_scope).call(
        state: params[:state], from: params[:from], to: params[:to]
      )
      pagy, settlements = pagy(filtered, limit: 25)
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
