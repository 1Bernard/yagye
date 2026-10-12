# frozen_string_literal: true

module Payments
  class SettlementDispatchesController < ApplicationController
    before_action :set_settlement

    def approve
      authorize @settlement, :approve_dispatch?

      result = CoreApiClient.new.approve_settlement_dispatch(
        @settlement.settlement_code,
        approved_by: current_user.user_code
      )

      if result.success?
        redirect_to settlement_path(@settlement.settlement_code),
                    notice: t("settlements.dispatch_approved")
      else
        redirect_to settlement_path(@settlement.settlement_code),
                    alert: t("settlements.dispatch_approval_failed")
      end
    end

    def reject
      authorize @settlement, :reject_dispatch?

      result = CoreApiClient.new.reject_settlement_dispatch(
        @settlement.settlement_code,
        rejected_by: current_user.user_code,
        reason: params[:reason]
      )

      if result.success?
        redirect_to settlement_path(@settlement.settlement_code),
                    notice: t("settlements.dispatch_rejected")
      else
        redirect_to settlement_path(@settlement.settlement_code),
                    alert: t("settlements.dispatch_rejection_failed")
      end
    end

    def approve_confirm_modal
      authorize @settlement, :approve_dispatch?
      render UI::ConfirmModal.new(
        title:         "Approve dispatch",
        body:          "The wire will be sent immediately and cannot be recalled.",
        warning_note:  "Only approve if you have verified the settlement batch amount and beneficiary details.",
        confirm_path:  approve_dispatch_settlement_path(@settlement.settlement_code),
        confirm_label: "Approve dispatch",
        success:       true
      )
    end

    private

    def set_settlement
      @settlement = decode_id(PortalSettlement, params[:id])
    end
  end
end
