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
      @application = PortalMerchantApplication.find(params[:id])
    end

    private

    def filters
      params.permit(:status, :q, :country).to_h.symbolize_keys
    end
  end
end
