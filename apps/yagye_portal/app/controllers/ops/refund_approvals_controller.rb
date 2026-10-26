# frozen_string_literal: true

module Ops
  class RefundApprovalsController < ApplicationController
    before_action :require_internal_staff!

    def index
      authorize :refund_approvals, :index?
      result = CoreApiClient.new.list_pending_refunds(limit: 50)
      @refunds = result.success? ? (result.body["data"] || []) : []
      render Ops::RefundApprovals::IndexView.new(refunds: @refunds)
    end

    def approve
      authorize :refund_approvals, :approve?
      refund_id = params[:id]
      result = CoreApiClient.new.approve_refund(
        refund_id,
        approved_by: current_user.user_code,
        reason:      params[:reason].to_s.strip.presence
      )
      if result.success?
        audit(action: "refund.approved", resource_type: "refund",
              outcome: "succeeded", resource_code: refund_id)
        redirect_to ops_refund_approvals_path, notice: "Refund approved and dispatched."
      else
        error_code = result.body&.dig("error", "code") || "approval_failed"
        message = case error_code
                  when "not_approvable" then "This refund cannot be approved in its current state."
                  when "validation_failed"
                    errors = result.body.dig("error", "errors")
                    errors&.dig("approved_by")&.first || "Approval failed — you may not approve your own refund."
                  else "Approval failed. Please try again."
                  end
        redirect_to ops_refund_approvals_path, alert: message
      end
    end

    def reject
      authorize :refund_approvals, :reject?
      refund_id = params[:id]
      reason    = params[:reason].to_s.strip.presence || "rejected_by_ops"
      result = CoreApiClient.new.reject_refund(
        refund_id,
        rejected_by: current_user.user_code,
        reason:      reason
      )
      if result.success?
        audit(action: "refund.rejected", resource_type: "refund",
              outcome: "succeeded", resource_code: refund_id)
        redirect_to ops_refund_approvals_path, notice: "Refund rejected."
      else
        redirect_to ops_refund_approvals_path, alert: "Rejection failed. Please try again."
      end
    end

    private

    def require_internal_staff!
      redirect_to root_path, alert: "Not authorised." unless current_user&.internal_staff?
    end
  end
end
