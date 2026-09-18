# frozen_string_literal: true

module Account
  class PricingController < ApplicationController
    def index
      authorize :settings, :index?
      result = core.get_merchant_pricing_plan(current_user.merchant_code)
      plan   = result.success? ? result.body : nil
      render Account::Pricing::IndexView.new(plan: plan)
    end

    def fee_invoices
      authorize :settings, :index?
      result   = core.list_fee_invoices(merchant_code: current_user.merchant_code)
      invoices = result.success? ? (result.body["data"] || []) : []
      render Account::Pricing::FeeInvoicesView.new(invoices: invoices)
    end

    private

    def core
      @core ||= CoreApiClient.new
    end
  end
end
