# frozen_string_literal: true

module Payments
  class SettlementBatchesController < ApplicationController
    def index
      authorize :settlement_batch, :index?, policy_class: SettlementBatchPolicy
      result   = core.list_settlement_batches(merchant_code: current_user.merchant_code)
      batches  = result.success? ? (result.body["data"] || []) : []
      dash     = core.get_merchant_settlement_dashboard(current_user.merchant_code)
      summary  = dash.success? ? dash.body : {}
      render Payments::SettlementBatches::IndexView.new(batches: batches, summary: summary)
    end

    def show
      authorize :settlement_batch, :index?, policy_class: SettlementBatchPolicy
      result = core.get_settlement_batch(params[:id])
      return redirect_to(settlement_batches_path, alert: "Batch not found.") unless result.success?

      render Payments::SettlementBatches::ShowView.new(batch: result.body)
    end

    private

    def core
      @core ||= CoreApiClient.new
    end
  end
end
