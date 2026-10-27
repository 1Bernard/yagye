# frozen_string_literal: true

module Ops
  class PayoutLedgerAuditController < ApplicationController
    before_action :require_internal_staff!

    def index
      authorize :payout_ledger_audit, :index?
      mode   = params[:mode].presence_in(%w[simulation live]) || Current.mode
      result = CoreApiClient.new.list_payout_ledger_gaps(mode: mode)
      @gaps  = result.success? ? (result.body["data"] || []) : []
      render Ops::PayoutLedgerAudit::IndexView.new(gaps: @gaps, mode: mode, count: @gaps.size)
    end

    private

    def require_internal_staff!
      redirect_to root_path, alert: "Not authorised." unless current_user&.internal_staff?
    end
  end
end
