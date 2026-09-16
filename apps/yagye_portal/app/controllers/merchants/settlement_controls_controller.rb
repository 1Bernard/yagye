# frozen_string_literal: true

module Merchants
  class SettlementControlsController < ApplicationController
    before_action :load_application

    def show
      authorize :merchants, :settlement_controls?
      client   = CoreApiClient.new
      result   = client.get_settlement_controls(@app.merchant_code)
      controls = result.success? ? result.body : {}
      staff    = User.where(kind: "internal_staff").order(:first_name, :last_name, :email)
      render Merchants::SettlementControlsView.new(application: @app, controls: controls, staff: staff)
    end

    def update
      authorize :merchants, :settlement_controls?
      threshold      = params[:approval_threshold].presence&.to_i
      approver_codes = Array(params[:approver_user_codes]).reject(&:blank?)

      result = CoreApiClient.new.upsert_settlement_controls(
        @app.merchant_code,
        approval_threshold:  threshold,
        approver_user_codes: approver_codes
      )

      if result.success?
        redirect_to merchant_settlement_controls_path(@app),
                    notice: "Settlement controls updated."
      else
        redirect_to merchant_settlement_controls_path(@app),
                    alert: result.error_message || "Could not update settlement controls."
      end
    end

    private

    def load_application
      @app = decode_id(PortalMerchantApplication)
      unless @app.merchant_code.present?
        redirect_to merchant_path(@app),
                    alert: "Merchant account must be approved before configuring settlement controls."
      end
    end
  end
end
