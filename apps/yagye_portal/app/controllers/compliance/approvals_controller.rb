# frozen_string_literal: true

module Compliance
  class ApprovalsController < ApplicationController
    def index
      authorize PortalAdjustmentApproval, :index?, policy_class: PortalAdjustmentApprovalPolicy
      scoped        = PortalAdjustmentApprovalPolicy::Scope.new(current_user, PortalAdjustmentApproval.all).resolve
      tab           = params[:tab].presence_in(%w[pending decided]) || "pending"
      can_decide    = PortalAdjustmentApprovalPolicy.new(current_user, nil).approve?
      pending_count = scoped.pending_review.count

      pagy, records = if tab == "decided"
        pagy(scoped.decided, limit: 25)
      else
        pagy(scoped.pending_review, limit: 25)
      end

      render Compliance::Approvals::IndexView.new(
        tab:           tab,
        records:       records,
        pagy:          pagy,
        pending_count: pending_count,
        can_decide:    can_decide
      )
    end

    def approve_modal
      record = decode_id(PortalAdjustmentApproval)
      authorize record, :approve?, policy_class: PortalAdjustmentApprovalPolicy
      render UI::ConfirmModal.new(
        title:        "Approve adjustment",
        body:         "This adjustment will proceed to the ledger. A second approver has already signed off.",
        warning_note: "This action cannot be undone.",
        confirm_path: compliance_approve_approval_path(record),
        confirm_label: "Approve adjustment",
        success:      true
      )
    end

    def approve
      record = decode_id(PortalAdjustmentApproval)
      authorize record, :approve?, policy_class: PortalAdjustmentApprovalPolicy
      result = CoreApiClient.new.approve_adjustment(break_id: record.core_break_id,
                                                    approved_by: current_user.user_code)
      if result.success?
        record.update!(state: "approved", approved_by: current_user.user_code, approved_at: Time.current)
        redirect_to compliance_approvals_path, notice: "Adjustment approved."
      else
        redirect_to compliance_approvals_path, alert: "Could not approve: #{result.error_message}"
      end
    end

    def reject
      record = decode_id(PortalAdjustmentApproval)
      authorize record, :reject?, policy_class: PortalAdjustmentApprovalPolicy
      reason = params[:reason].to_s.strip
      return redirect_to(compliance_approvals_path, alert: "Rejection reason is required.") if reason.blank?

      result = CoreApiClient.new.reject_adjustment(break_id: record.core_break_id,
                                                   rejected_by: current_user.user_code,
                                                   rejected_reason: reason)
      if result.success?
        record.update!(state: "rejected", rejected_reason: reason,
                       rejected_by: current_user.user_code, rejected_at: Time.current)
        redirect_to compliance_approvals_path, notice: "Adjustment rejected."
      else
        redirect_to compliance_approvals_path, alert: "Could not reject: #{result.error_message}"
      end
    end
  end
end
