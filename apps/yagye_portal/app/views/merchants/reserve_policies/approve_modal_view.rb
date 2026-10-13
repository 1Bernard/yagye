# frozen_string_literal: true

module Merchants
  module ReservePolicies
    class ApproveModalView < ApplicationComponent
      include UI::Theme

      def initialize(application:, policy_id:)
        @app       = application
        @policy_id = policy_id
      end

      def view_template
        render UI::ConfirmModal.new(
          title:         "Approve reserve policy",
          body:          "Approving this policy for #{@app.legal_name} will activate fund withholding on the next settlement. You must be a different person from the policy creator (SoD requirement).",
          warning_note:  "Once approved, the reserve applies to all live settlements immediately.",
          confirm_path:  approve_merchant_reserve_policy_path(@app, @policy_id),
          confirm_label: "Approve policy",
          success:       true
        )
      end
    end
  end
end
