# frozen_string_literal: true

module Account
  class SettingsController < ApplicationController
    def index
      authorize :settings, :index?
      tab = params[:tab].presence_in(%w[profile security notifications allowlists sso verification payouts]) || "profile"
      ip_allowlists     = PortalIpAllowlist.for_merchant(current_user.merchant_code).order(:created_at)
      msisdn_allowlists = PortalMsisdnAllowlist.for_merchant(current_user.merchant_code).order(:created_at)
      audit_events      = current_user.user_audit_events.recent.limit(15)
      sso_configs       = tab == "sso" ? SsoConfiguration.order(:name) : []
      tier              = current_user.merchant_tier || 1
      payout_controls   = tab == "payouts" && current_user.merchant_user? ? load_payout_controls : {}
      render Settings::IndexView.new(tab: tab, current_user: current_user,
                                     ip_allowlists: ip_allowlists, msisdn_allowlists: msisdn_allowlists,
                                     audit_events: audit_events, sso_configs: sso_configs, tier: tier,
                                     payout_controls: payout_controls)
    end

    def update_profile
      authorize :settings, :update?
      changing_theme    = params[:theme_preference].present?
      changing_language = params[:language_preference].present?

      if current_user.update(profile_params)
        session[:locale] = current_user.language_preference if changing_language
        unless changing_theme || changing_language
          UserAuditEvents::Record.call(user: current_user, event_type: :profile_updated, request: request)
        end
        notice = if changing_theme    then "Theme updated."
        elsif changing_language then "Language updated."
        else "Profile updated."
        end
        redirect_to settings_path(tab: "profile"), notice: notice
      else
        redirect_to settings_path(tab: "profile"),
                    alert: current_user.errors.full_messages.first || "Could not update profile."
      end
    end

    def update_password
      authorize :settings, :update?
      unless current_user.valid_password?(params[:current_password])
        return redirect_to settings_path(tab: "security"), alert: "Current password is incorrect."
      end
      if params[:password] != params[:password_confirmation]
        return redirect_to settings_path(tab: "security"), alert: "New passwords do not match."
      end
      current_user.update!(password: params[:password])
      bypass_sign_in(current_user)
      UserAuditEvents::Record.call(user: current_user, event_type: :password_changed, request: request)
      redirect_to settings_path(tab: "security"), notice: "Password updated."
    end

    private

    def load_payout_controls
      result = CoreApiClient.new.get_settlement_controls(current_user.merchant_code)
      result.success? ? result.body : {}
    rescue StandardError
      {}
    end

    def profile_params
      if params[:user]
        params.require(:user).permit(:first_name, :last_name)
      else
        params.permit(:theme_preference, :language_preference)
      end
    end
  end
end
