# frozen_string_literal: true

module Merchants
  class MerchantsController < ApplicationController
    def index
      authorize :merchants, :index?
      scope      = Merchants::MerchantsQuery.new.call(filters)
      @pagy, @merchants = pagy(scope, limit: 25)
      @status    = params[:status]
      @query     = params[:q]
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
