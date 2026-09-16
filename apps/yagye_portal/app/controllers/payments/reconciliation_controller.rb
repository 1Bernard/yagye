# frozen_string_literal: true

module Payments
  class ReconciliationController < ApplicationController
    def index
      authorize :reconciliation, :index?
      result = CoreApiClient.new.list_all_reconciliation_breaks
      breaks = result.success? ? (result.body["data"] || []) : []
      render Payments::Reconciliation::IndexView.new(breaks: breaks)
    end

    def show
      authorize :reconciliation, :show?
      result = CoreApiClient.new.get_reconciliation_break(params[:id])
      if result.success?
        render Payments::Reconciliation::ShowView.new(recon_break: result.body)
      else
        redirect_to reconciliation_path, alert: "Reconciliation break not found."
      end
    end

    def propose_adjustment
      authorize :reconciliation, :propose_adjustment?
      result = CoreApiClient.new.propose_reconciliation_adjustment(
        params[:id],
        proposed_by:     current_user.user_code,
        amount:          params[:amount].to_i,
        direction:       params[:direction],
        resolution_code: params[:resolution_code],
        resolution_note: params[:resolution_note].presence
      )
      if result.success?
        redirect_to reconciliation_break_path(params[:id]),
                    notice: "Adjustment proposed and pending approval."
      else
        redirect_to reconciliation_break_path(params[:id]),
                    alert: "Failed to propose adjustment: #{result.error_message}"
      end
    end
  end
end
