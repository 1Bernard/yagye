# frozen_string_literal: true

module Account
  class SettingsController < ApplicationController
    def index
      authorize :settings, :index?
      tab = params[:tab].presence_in(%w[profile security notifications allowlists sso verification payouts]) || "profile"
      ip_allowlists        = PortalIpAllowlist.kept.for_merchant(current_user.merchant_code).order(:created_at)
      ip_blocklists        = PortalIpBlocklist.kept.for_merchant(current_user.merchant_code).order(:created_at)
      msisdn_allowlists    = PortalMsisdnAllowlist.kept.for_merchant(current_user.merchant_code).order(:created_at)
      msisdn_blocklists    = PortalMsisdnBlocklist.kept.for_merchant(current_user.merchant_code).order(:created_at)
      email_blocklists     = PortalEmailBlocklist.kept.for_merchant(current_user.merchant_code).order(:created_at)
      kyb_application      = tab == "verification" && current_user.merchant_user? ? PortalMerchantApplication.find_by(merchant_code: current_user.merchant_code) : nil
      branding             = tab == "verification" && current_user.merchant_user? ? PortalMerchantBranding.find_or_initialize_for(current_user.merchant_code) : nil
      audit_events         = current_user.user_audit_events.recent.limit(15)
      sso_configs          = tab == "sso" ? SsoConfiguration.order(:name) : []
      tier                 = current_user.merchant_tier || 1
      payout_controls, payout_destinations = tab == "payouts" && current_user.merchant_user? ? load_payouts_data : [ {}, [] ]
      render Settings::IndexView.new(tab: tab, current_user: current_user,
                                     ip_allowlists: ip_allowlists, ip_blocklists: ip_blocklists,
                                     msisdn_allowlists: msisdn_allowlists,
                                     msisdn_blocklists: msisdn_blocklists,
                                     email_blocklists: email_blocklists,
                                     branding: branding,
                                     kyb_application: kyb_application,
                                     audit_events: audit_events, sso_configs: sso_configs, tier: tier,
                                     payout_controls: payout_controls,
                                     payout_destinations: payout_destinations)
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

    def update_notifications
      authorize :settings, :update?
      events   = params[:notifications]&.to_unsafe_h || {}
      channels = params[:channels]&.to_unsafe_h || {}

      prefs = {
        "events" => User::NOTIFICATION_EVENT_KEYS.index_with { |k| events[k] == "1" },
        "channels" => User::NOTIFICATION_CHANNEL_KEYS.index_with { |k| channels[k] == "1" }
      }

      current_user.update!(notification_preferences: prefs)
      redirect_to settings_path(tab: "notifications"), notice: "Notification preferences saved."
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

    def load_payouts_data
      client          = CoreApiClient.new
      controls_result = client.get_settlement_controls(current_user.merchant_code)
      controls        = controls_result.success? ? controls_result.body : {}
      dest_result     = client.list_payout_destinations(current_user.merchant_code)
      destinations    = dest_result.success? ? (dest_result.body["data"] || []) : []
      [ controls, destinations ]
    rescue StandardError
      [ {}, [] ]
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
