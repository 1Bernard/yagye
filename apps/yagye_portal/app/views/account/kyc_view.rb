# frozen_string_literal: true

module Account
  class KycView < ApplicationComponent
    def initialize(tier:)
      @tier = tier
    end

    def view_template
      render Layout::Shell.new(
        active_nav:  :settings,
        title:       "Identity Verification",
        breadcrumbs: [
          { label: "Settings", url: settings_path(tab: "verification") },
          { label: "Identity Verification" }
        ]
      ) do
        render Settings::VerificationPanel.new(tier: @tier)
      end
    end
  end
end
