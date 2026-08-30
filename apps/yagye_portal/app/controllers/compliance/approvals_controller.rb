# frozen_string_literal: true

module Compliance
  class ApprovalsController < ApplicationController
    def index
      authorize PortalAdjustmentApproval, :index?, policy_class: PortalAdjustmentApprovalPolicy
      scoped    = PortalAdjustmentApprovalPolicy::Scope.new(current_user, PortalAdjustmentApproval.all).resolve
      pending   = scoped.pending_review
      decided   = scoped.decided.limit(50)
      can_decide = PortalAdjustmentApprovalPolicy.new(current_user, nil).approve?
      render Compliance::Approvals::IndexView.new(pending: pending, decided: decided, can_decide: can_decide)
    end

    def approve
      record = PortalAdjustmentApproval.find(params[:id])
      authorize record, :approve?, policy_class: PortalAdjustmentApprovalPolicy
      result = CoreApiClient.new.approve_adjustment(break_id: record.core_break_id,
                                                    approved_by: current_user.email)
      if result.success?
        record.update!(state: "approved", approved_by: current_user.email, approved_at: Time.current)
        redirect_to compliance_approvals_path, notice: "Adjustment approved."
      else
        redirect_to compliance_approvals_path, alert: "Could not approve: #{result.error_message}"
      end
    end

    def reject
      record = PortalAdjustmentApproval.find(params[:id])
      authorize record, :reject?, policy_class: PortalAdjustmentApprovalPolicy
      reason = params[:reason].to_s.strip
      return redirect_to(compliance_approvals_path, alert: "Rejection reason is required.") if reason.blank?

      result = CoreApiClient.new.reject_adjustment(break_id: record.core_break_id,
                                                   rejected_reason: reason)
      if result.success?
        record.update!(state: "rejected", rejected_reason: reason)
        redirect_to compliance_approvals_path, notice: "Adjustment rejected."
      else
        redirect_to compliance_approvals_path, alert: "Could not reject: #{result.error_message}"
      end
    end
  end
end
