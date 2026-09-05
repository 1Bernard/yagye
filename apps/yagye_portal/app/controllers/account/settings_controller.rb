# frozen_string_literal: true

module Account
  class SettingsController < ApplicationController
    def index
      authorize :settings, :index?
      tab = params[:tab].presence_in(%w[profile security notifications allowlists]) || "profile"
      ip_allowlists     = PortalIpAllowlist.for_merchant(current_user.merchant_code).order(:created_at)
      msisdn_allowlists = PortalMsisdnAllowlist.for_merchant(current_user.merchant_code).order(:created_at)
      audit_events      = current_user.user_audit_events.recent.limit(15)
      render Settings::IndexView.new(tab: tab, current_user: current_user,
                                     ip_allowlists: ip_allowlists, msisdn_allowlists: msisdn_allowlists,
                                     audit_events: audit_events)
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
        ip_allowlists     = PortalIpAllowlist.for_merchant(current_user.merchant_code).order(:created_at)
        msisdn_allowlists = PortalMsisdnAllowlist.for_merchant(current_user.merchant_code).order(:created_at)
        audit_events      = current_user.user_audit_events.recent.limit(15)
        render Settings::IndexView.new(
          tab: "profile",
          current_user: current_user,
          ip_allowlists: ip_allowlists,
          msisdn_allowlists: msisdn_allowlists,
          audit_events: audit_events,
          profile_dialog_open: true
        ), status: :unprocessable_entity
      end
    end

    def update_password
      authorize :settings, :update?
      unless current_user.valid_password?(params[:current_password])
        return redirect_to settings_path(tab: "security"),
                           alert: "Current password is incorrect."
      end
      if params[:password] != params[:password_confirmation]
        return redirect_to settings_path(tab: "security"),
                           alert: "New passwords do not match."
      end
      current_user.update!(password: params[:password])
      bypass_sign_in(current_user)
      UserAuditEvents::Record.call(user: current_user, event_type: :password_changed, request: request)
      redirect_to settings_path(tab: "security"), notice: "Password updated."
    end

    private

    def profile_params
      if params[:user]
        params.require(:user).permit(:first_name, :last_name)
      else
        params.permit(:theme_preference, :language_preference)
      end
    end
  end
end
