# frozen_string_literal: true

module Account
  class SettingsController < ApplicationController
    def index
      authorize :settings, :index?
      tab = params[:tab].presence_in(%w[profile security notifications allowlists]) || "profile"
      render Settings::IndexView.new(tab: tab, current_user: current_user)
    end

    def update_profile
      authorize :settings, :update?
      if current_user.update(profile_params)
        redirect_to settings_path(tab: "profile"), notice: "Profile updated."
      else
        redirect_to settings_path(tab: "profile"),
                    alert: current_user.errors.full_messages.first
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
      redirect_to settings_path(tab: "security"), notice: "Password updated."
    end

    private

    def profile_params
      params.permit(:first_name, :last_name)
    end
  end
end
