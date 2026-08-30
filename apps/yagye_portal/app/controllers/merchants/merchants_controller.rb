# frozen_string_literal: true

module Merchants
  class MerchantsController < ApplicationController
    def index
      authorize :merchants, :index?
      pagy, merchants = pagy(Merchants::MerchantsQuery.new.call(filters), limit: 25)
      render Merchants::IndexView.new(
        merchants: merchants, pagy: pagy,
        status: params[:status], query: params[:q]
      )
    end

    def show
      authorize :merchants, :show?
      application = PortalMerchantApplication.find(params[:id])
      render Merchants::ShowView.new(application: application)
    end

    def update
      authorize :merchants, :update?
      application = PortalMerchantApplication.find(params[:id])
      new_status  = params[:status].to_s.strip
      result = CoreApiClient.new.update_merchant_status(
        application.merchant_code || application.application_code,
        status:       new_status,
        reviewed_by:  current_user.email
      )
      if result.success?
        redirect_to merchant_path(application), notice: "Merchant status updated to #{new_status.humanize}."
      else
        redirect_to merchant_path(application), alert: result.error_message
      end
    end

    private

    def filters
      params.permit(:status, :q, :country).to_h.symbolize_keys
    end
  end
end
