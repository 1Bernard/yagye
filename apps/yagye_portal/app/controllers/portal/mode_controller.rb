# frozen_string_literal: true

module Portal
  # Stores the merchant's chosen mode (test | live) in the session.
  # Ops users have no mode — this action is merchant-only.
  class ModeController < ApplicationController
    skip_before_action :verify_authenticity_token, raise: false

    def update
      skip_authorization

      requested = params[:mode].to_s
      unless requested.in?(%w[test live])
        redirect_back_or_to authenticated_root_path, alert: "Invalid mode."
        return
      end

      if requested == "live" && !live_mode_allowed?
        redirect_back_or_to authenticated_root_path,
                             alert: "Live mode has not been enabled for your account yet."
        return
      end

      session[:portal_mode] = requested
      redirect_back_or_to authenticated_root_path,
                           notice: "Switched to #{requested.upcase} mode."
    end

    private

    def live_mode_allowed?
      return false unless current_user.merchant_user?
      PortalMerchant.find_for(current_user.merchant_code)&.live_mode_enabled? || false
    end
  end
end
