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
  end
end
