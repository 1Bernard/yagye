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

    private

    def set_settlement
      @settlement = decode_id(PortalSettlement, params[:id])
    end
  end
end
