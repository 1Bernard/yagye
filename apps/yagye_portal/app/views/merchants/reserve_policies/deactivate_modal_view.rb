# frozen_string_literal: true

module Merchants
  module ReservePolicies
    class DeactivateModalView < ApplicationComponent
      include UI::Theme

      def initialize(application:, policy_id:)
        @app       = application
        @policy_id = policy_id
      end

      def view_template
        render UI::ConfirmModal.new(
          title:         "Deactivate reserve policy",
          body:          "No further funds will be withheld from #{@app.legal_name}'s settlements. Existing holds are not affected and will release on their scheduled date.",
          confirm_path:  deactivate_merchant_reserve_policy_path(@app, @policy_id),
          confirm_label: "Deactivate policy",
          danger:        true
        )
      end
    end
  end
end
