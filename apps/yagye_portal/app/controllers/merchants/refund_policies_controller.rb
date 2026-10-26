# frozen_string_literal: true

module Merchants
  class RefundPoliciesController < ApplicationController
    before_action :load_application

    def show
      authorize :merchants, :settlement_controls?
      result = CoreApiClient.new.get_checkout_config(@app.merchant_code)
      config = result.success? ? result.body : {}
      render Merchants::RefundPolicyView.new(application: @app, config: config)
    end

    def update
      authorize :merchants, :settlement_controls?

      window_days  = params[:refund_window_days].presence&.to_i
      partial      = params[:partial_refunds_enabled] == "1"
      threshold_ghs = params[:requires_approval_above_ghs].presence&.to_f
      threshold_pesewas = threshold_ghs ? (threshold_ghs * 100).round : nil

      result = CoreApiClient.new.update_refund_policy(
        @app.merchant_code,
        refund_window_days:              window_days,
        partial_refunds_enabled:         partial,
        requires_approval_above_pesewas: threshold_pesewas
      )

      if result.success?
        redirect_to merchant_refund_policy_path(@app),
                    notice: "Refund policy updated."
      else
        redirect_to merchant_refund_policy_path(@app),
                    alert: result.error_message || "Could not update refund policy."
      end
    end

    private

    def load_application
      @app = find_owned!(PortalMerchantApplication)
      unless @app.merchant_code.present?
        redirect_to merchant_path(@app),
                    alert: "Merchant account must be approved before configuring refund policy."
      end
    end
  end
end
