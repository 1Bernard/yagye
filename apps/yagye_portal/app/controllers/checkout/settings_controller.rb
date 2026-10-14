# frozen_string_literal: true

module Checkout
  class SettingsController < ApplicationController
    def index
      authorize :settings, :index?
      @tab             = params[:tab].presence_in(%w[methods analytics]) || "methods"
      allowed_methods  = load_allowed_methods
      analytics        = @tab == "analytics" ? load_analytics : nil

      render Checkout::Settings::IndexView.new(
        tab:             @tab,
        allowed_methods: allowed_methods,
        analytics:       analytics
      )
    end

    def update_payment_methods
      authorize :settings, :update?
      allowed = Array(params[:allowed_methods]).select { |m| %w[mobile_money card bank_transfer].include?(m) }

      if allowed.empty?
        return redirect_to checkout_settings_path(tab: "methods"),
                           alert: "At least one payment method must be enabled."
      end

      result = CoreApiClient.new.update_checkout_config(current_user.merchant_code, allowed_methods: allowed)

      if result.success?
        redirect_to checkout_settings_path(tab: "methods"), notice: "Payment methods updated."
      else
        redirect_to checkout_settings_path(tab: "methods"), alert: "Could not save payment method settings."
      end
    end

    private

    def load_allowed_methods
      result = CoreApiClient.new.get_checkout_config(current_user.merchant_code)
      result.success? ? (result.body["allowed_methods"] || %w[mobile_money card bank_transfer]) : %w[mobile_money card bank_transfer]
    rescue StandardError
      %w[mobile_money card bank_transfer]
    end

    def load_analytics
      result = CoreApiClient.new.get_checkout_analytics(
        current_user.merchant_code,
        from: 30.days.ago.to_date.to_s
      )
      result.success? ? result.body : {}
    rescue StandardError
      {}
    end
  end
end
