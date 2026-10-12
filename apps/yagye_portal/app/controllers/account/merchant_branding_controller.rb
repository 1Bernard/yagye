# frozen_string_literal: true

module Account
  class MerchantBrandingController < ApplicationController
    before_action :require_merchant_user!

    def update
      branding = PortalMerchantBranding.find_or_initialize_for(current_user.merchant_code)
      authorize branding, policy_class: PortalMerchantBrandingPolicy

      branding.display_name = params[:display_name].to_s.strip.presence
      branding.logo         = params[:logo] if params[:logo].present?

      if branding.save
        redirect_to settings_path(tab: "verification"), notice: "Business profile updated."
      else
        redirect_to settings_path(tab: "verification"),
                    alert: branding.errors.full_messages.first || "Could not update profile."
      end
    end

    def remove_logo_modal
      branding = PortalMerchantBranding.find_or_initialize_for(current_user.merchant_code)
      authorize branding, :update?, policy_class: PortalMerchantBrandingPolicy
      render UI::ConfirmModal.new(
        title:          "Remove logo",
        body:           "Your merchant logo will be removed. You can upload a new one at any time.",
        confirm_path:   settings_remove_merchant_logo_path,
        confirm_method: "delete",
        confirm_label:  "Remove logo",
        danger:         true
      )
    end

    def remove_logo
      branding = PortalMerchantBranding.find_or_initialize_for(current_user.merchant_code)
      authorize branding, :update?, policy_class: PortalMerchantBrandingPolicy
      branding.logo.purge if branding.logo.attached?
      redirect_to settings_path(tab: "verification"), notice: "Logo removed."
    end

    private

    def require_merchant_user!
      redirect_to settings_path unless current_user.merchant_user?
    end
  end
end
