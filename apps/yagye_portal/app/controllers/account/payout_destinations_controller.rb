# frozen_string_literal: true

module Account
  class PayoutDestinationsController < ApplicationController
    before_action :require_merchant_user!
    skip_before_action :require_merchant_user!, only: %i[verify_modal verify reject_modal reject]

    def create
      skip_authorization
      attrs = build_attrs
      result = CoreApiClient.new.create_payout_destination(current_user.merchant_code, attrs)

      if result.success?
        redirect_to settings_path(tab: "payouts"), notice: "Payout destination added."
      else
        redirect_to settings_path(tab: "payouts"),
                    alert: result.body["message"].presence || "Could not add destination."
      end
    end

    def set_default
      skip_authorization
      result = CoreApiClient.new.update_default_payout_destination(
        current_user.merchant_code,
        params[:id]
      )

      if result.success?
        redirect_to settings_path(tab: "payouts"), notice: "Default destination updated."
      else
        redirect_to settings_path(tab: "payouts"),
                    alert: result.body["message"].presence || "Could not update default."
      end
    end

    def remove_modal
      skip_authorization
      render UI::ConfirmModal.new(
        title:          "Remove payout account",
        body:           "This payout account will be permanently removed. This cannot be undone.",
        confirm_path:   settings_payout_destination_remove_path(params[:id]),
        confirm_method: "delete",
        confirm_label:  "Remove account",
        danger:         true
      )
    end

    def destroy
      skip_authorization
      result = CoreApiClient.new.deactivate_payout_destination(
        current_user.merchant_code,
        params[:id]
      )

      if result.success?
        redirect_to settings_path(tab: "payouts"), notice: "Destination removed."
      else
        redirect_to settings_path(tab: "payouts"),
                    alert: result.body["message"].presence || "Could not remove destination."
      end
    end

    def verify_modal
      authorize :payout_destinations, :verify?
      render UI::ConfirmModal.new(
        title:          "Approve payout destination",
        body:           "Mark this account as verified. You cannot be the same user who added it (SoD).",
        confirm_path:   verify_settings_payout_destination_path(params[:id]),
        confirm_method: "post",
        confirm_label:  "Approve",
        success:        true,
        hidden_fields:  { verified_by: current_user.user_code, merchant_code: params[:merchant_code] }
      )
    end

    def verify
      authorize :payout_destinations, :verify?
      merchant_code = params[:merchant_code].presence || current_user.merchant_code
      result = CoreApiClient.new.approve_payout_destination(
        merchant_code,
        params[:id],
        verified_by: current_user.user_code
      )
      target = after_verify_path
      if result.success?
        redirect_to target, notice: "Destination verified."
      else
        msg = result.body.dig("errors")&.values&.flatten&.first ||
              result.body["message"].presence || "Could not verify destination."
        redirect_to target, alert: msg
      end
    end

    def reject_modal
      authorize :payout_destinations, :verify?
      render UI::ConfirmModal.new(
        title:          "Reject payout destination",
        body:           "Mark this account as failed verification. The merchant will need to add a new destination.",
        confirm_path:   reject_settings_payout_destination_path(params[:id]),
        confirm_method: "post",
        confirm_label:  "Reject",
        danger:         true,
        hidden_fields:  { merchant_code: params[:merchant_code] }
      )
    end

    def reject
      authorize :payout_destinations, :verify?
      merchant_code = params[:merchant_code].presence || current_user.merchant_code
      result = CoreApiClient.new.reject_payout_destination(merchant_code, params[:id])
      target = after_verify_path
      if result.success?
        redirect_to target, notice: "Destination rejected."
      else
        redirect_to target, alert: "Could not reject destination."
      end
    end

    private

    def after_verify_path
      current_user.internal_staff? ? merchants_path : settings_path(tab: "payouts")
    end

    def require_merchant_user!
      redirect_to settings_path unless current_user.merchant_user?
    end

    def build_attrs
      kind = params[:kind].presence_in(%w[mobile_money bank]) || "mobile_money"

      account_details =
        if kind == "mobile_money"
          { msisdn: params[:msisdn], network: params[:network] }
        else
          {
            account_number: params[:account_number],
            account_name:   params[:account_name],
            bank_code:      params[:bank_code]
          }
        end

      {
        kind:            kind,
        mode:            Current.mode || "live",
        currency:        "GHS",
        account_details: account_details,
        added_by:        current_user.user_code
      }
    end
  end
end
