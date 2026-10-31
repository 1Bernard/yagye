# frozen_string_literal: true

module Risk
  class ScreeningHitsController < ApplicationController
    before_action :require_internal_staff!
    before_action :require_risk_view!

    def index
      skip_authorization

      list_type = params[:list_type].presence_in(%w[sanctions pep adverse_media])
      result    = core_api.get("/internal/risk/screening-hits",
                               list_type: list_type, limit: 50, after: params[:after])
      records   = result.success? ? result.body["data"] : []
      pagy_meta = result.success? ? result.body : {}

      render Risk::ScreeningHits::IndexView.new(
        list_type:   list_type || "all",
        records:     records,
        has_more:    pagy_meta["has_more"] || false,
        next_cursor: pagy_meta["next"],
        can_dispose: current_user.permitted?("risk.disposition")
      )
    end

    def dispose
      skip_authorization
      raise Pundit::NotAuthorizedError unless current_user.permitted?("risk.disposition")

      result = core_api.post(
        "/internal/risk/screening-hits/#{params[:id]}/dispose",
        merchant_id:        params[:merchant_id],
        status:             params[:status],
        disposition_reason: params[:disposition_reason],
        dispositioned_by:   current_user.user_code
      )

      if result.success?
        redirect_to risk_screening_hits_path, notice: "Hit dispositioned."
      else
        redirect_to risk_screening_hits_path,
                    alert: result.error_message || "Failed to dispose hit."
      end
    end

    private

    def require_internal_staff!
      redirect_to root_path, status: :see_other unless current_user.internal_staff?
    end

    def require_risk_view!
      raise Pundit::NotAuthorizedError unless current_user.permitted?("risk.view")
    end

    def core_api
      @core_api ||= CoreApiClient.new
    end
  end
end
