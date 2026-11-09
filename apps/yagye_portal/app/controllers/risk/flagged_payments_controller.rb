# frozen_string_literal: true

module Risk
  class FlaggedPaymentsController < ApplicationController
    before_action :require_internal_staff!
    before_action :require_risk_view!

    def index
      skip_authorization

      tab     = params[:tab].presence_in(%w[review block]) || "review"
      result  = core_api.get("/internal/risk/flagged-payments", decision: tab, limit: 25, after: params[:after])
      records = result.success? ? result.body["data"] : []
      pagy_meta = result.success? ? result.body : {}

      render Risk::FlaggedPayments::IndexView.new(
        tab:        tab,
        records:    records,
        has_more:   pagy_meta["has_more"] || false,
        next_cursor: pagy_meta["next"],
        can_dispose: current_user.permitted?("risk.disposition")
      )
    end

    def show
      skip_authorization

      result = core_api.get("/internal/risk/flagged-payments/#{params[:id]}")
      return redirect_to risk_flagged_payments_path, alert: "Not found." unless result.success?

      payment = result.body["payment"]
      labels  = result.body["labels"]

      render Risk::FlaggedPayments::ShowView.new(
        payment:     payment,
        labels:      labels,
        can_dispose: current_user.permitted?("risk.disposition")
      )
    end

    def sar
      skip_authorization

      result = core_api.get("/internal/risk/flagged-payments/#{params[:id]}")
      return redirect_to risk_flagged_payments_path, alert: "Not found." unless result.success?

      payment = result.body["payment"]
      labels  = result.body["labels"]

      pdf = Risk::SarPdfGenerator.new(payment: payment, labels: labels).generate

      send_data pdf.render,
                filename:    "SAR-#{payment['public_id']}-#{Date.today}.pdf",
                type:        "application/pdf",
                disposition: "attachment"
    end

    def dispose
      skip_authorization
      raise Pundit::NotAuthorizedError unless current_user.permitted?("risk.disposition")

      result = core_api.post(
        "/internal/risk/flagged-payments/#{params[:id]}/dispose",
        label:             params[:label],
        dispositioned_by:  current_user.user_code,
        note:              params[:note]
      )

      if result.success?
        redirect_to risk_flagged_payment_path(params[:id]), notice: "Case dispositioned."
      else
        redirect_to risk_flagged_payment_path(params[:id]),
                    alert: result.error_message || "Failed to dispose case."
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
