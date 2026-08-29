# frozen_string_literal: true

module Account
  class SettingsController < ApplicationController
    def index
      authorize :settings, :index?
      tab = params[:tab].presence_in(%w[profile security notifications allowlists]) || "profile"
      render Settings::IndexPage.new(tab: tab, current_user: current_user)
    end
  end
end
