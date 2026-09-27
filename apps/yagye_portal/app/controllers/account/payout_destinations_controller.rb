# frozen_string_literal: true

module Account
  class PayoutDestinationsController < ApplicationController
    before_action :require_merchant_user!

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
      result = CoreApiClient.new.set_default_payout_destination(
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

    private

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
