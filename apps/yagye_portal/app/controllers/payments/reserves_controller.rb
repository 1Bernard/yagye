# frozen_string_literal: true

module Payments
  class ReservesController < ApplicationController
    def index
      authorize :reserve, :index?, policy_class: ReservePolicy
      result = CoreApiClient.new.get_reserves(
        current_user.merchant_code,
        limit: 50,
        offset: (params[:page].to_i.clamp(1, 9999) - 1) * 50
      )
      data = result.success? ? result.body : {}

      render Payments::Reserves::IndexView.new(
        policy:  data["policy"],
        summary: data["summary"] || {},
        holds:   data["holds"]   || [],
        page:    params[:page].to_i.clamp(1, 9999),
        total:   data.dig("meta", "total").to_i
      )
    end

    def acknowledge
      authorize :reserve, :index?, policy_class: ReservePolicy

      result = CoreApiClient.new.acknowledge_reserve_policy(
        params[:id],
        acknowledged_by: current_user.user_code
      )

      if result.success?
        AuditLog.record(
          actor:         current_user,
          action:        "reserve_policy.acknowledged",
          resource_type: "merchant",
          resource_code: current_user.merchant_code,
          outcome:       "succeeded"
        )
        redirect_to reserves_path,
                    notice: "Reserve policy acknowledged. Funds will be withheld from your next settlement."
      else
        redirect_to reserves_path, alert: result.error_message
      end
    end
  end
end
