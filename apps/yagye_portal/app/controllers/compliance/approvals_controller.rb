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
        tab:               tab,
        records:           records,
        pagy:              pagy,
        pending_count:     pending_count,
        can_decide:        can_decide,
        current_user_code: current_user.user_code
      )
    end

    def approve_modal
      record = decode_id(PortalAdjustmentApproval)
      authorize record, :approve?, policy_class: PortalAdjustmentApprovalPolicy

      if record.proposed_by == current_user.user_code
        return render UI::ConfirmModal.new(
          title:        "Cannot approve",
          body:         "You proposed this adjustment. A different ops member must approve it (maker-checker).",
          confirm_path: compliance_approvals_path,
          confirm_label: "OK",
          danger:       false
        )
      end

      render UI::ConfirmModal.new(
        title:         "Approve adjustment",
        body:          "The correcting ledger entry will be posted and the reconciliation break closed.",
        warning_note:  "This action cannot be undone.",
        confirm_path:  compliance_approve_approval_path(record),
        confirm_label: "Approve adjustment",
        success:       true
      )
    end

    def approve
      record = decode_id(PortalAdjustmentApproval)
      authorize record, :approve?, policy_class: PortalAdjustmentApprovalPolicy

      if record.proposed_by == current_user.user_code
        return redirect_to compliance_approvals_path,
                            alert: "You proposed this adjustment and cannot also approve it (maker-checker)."
      end

      result = CoreApiClient.new.approve_adjustment(break_id: record.core_break_id,
                                                    approved_by: current_user.user_code)
      if result.success?
        record.update!(state: "approved", approved_by: current_user.user_code, approved_at: Time.current)
        redirect_to compliance_approvals_path, notice: "Adjustment approved."
      else
        msg = sod_or_default(result, "Could not approve adjustment.")
        redirect_to compliance_approvals_path, alert: msg
      end
    end

    def reject_modal
      record = decode_id(PortalAdjustmentApproval)
      authorize record, :reject?, policy_class: PortalAdjustmentApprovalPolicy
      render Compliance::Approvals::RejectModalView.new(record: record)
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

    private

    def sod_or_default(result, default_msg)
      body = result.body
      if body.is_a?(Hash) && body["error"].to_s.include?("SoD")
        "You proposed this adjustment and cannot also approve it (maker-checker)."
      else
        "#{default_msg} #{result.error_message}".strip
      end
    end
  end
end
