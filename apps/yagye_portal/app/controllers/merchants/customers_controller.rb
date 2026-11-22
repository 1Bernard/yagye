# frozen_string_literal: true

module Merchants
  class CustomersController < ApplicationController
    before_action :require_internal_staff!
    before_action :load_merchant_application

    def index
      authorize :customer, :index?, policy_class: CustomerPolicy

      result    = core.list_customers(merchant_code: @merchant_code)
      customers = result.success? ? (result.body["data"] || []) : []
      customers = filter_customers(customers)

      refs     = customers.filter_map { |c| c["merchant_customer_ref"] }.uniq
      scope    = Payment.for_merchant(@merchant_code)
      query    = Payments::CustomerStatsQuery.new(scope)
      stats    = query.call(refs: refs)
      networks = query.primary_networks(refs: refs)

      render Payments::Customers::IndexView.new(
        customers:   customers,
        query:       params[:q],
        stats:       stats,
        networks:    networks,
        back_path:   merchant_path(params[:id]),
        merchant:    @application
      )
    end

    def show
      authorize :customer, :show?, policy_class: CustomerPolicy

      result = core.get_customer(params[:customer_id])
      return redirect_to(merchant_customers_path(params[:id]), alert: "Customer not found.") unless result.success?

      customer = result.body
      ref      = customer["merchant_customer_ref"]
      scope    = Payment.for_merchant(@merchant_code)
      query    = Payments::CustomerStatsQuery.new(scope)
      stat     = ref.present? ? query.call(refs: [ ref ])[ref] : nil
      network  = ref.present? ? query.primary_networks(refs: [ ref ])[ref] : nil

      render Payments::Customers::ShowView.new(customer: customer, stat: stat, network: network)
    end

    private

    def load_merchant_application
      @application  = find_owned!(PortalMerchantApplication)
      @merchant_code = @application.merchant_code
      redirect_to merchants_path, alert: "Merchant not found." unless @merchant_code.present?
    end

    def require_internal_staff!
      redirect_to root_path, alert: "Not authorized." unless current_user.internal_staff?
    end

    def filter_customers(customers)
      return customers if params[:q].blank?

      q = params[:q].to_s.downcase
      customers.select do |c|
        [ c["merchant_customer_ref"], c["id"], c["name"], c["msisdn"], c["email"] ]
          .any? { |v| v.to_s.downcase.include?(q) }
      end
    end

    def core
      @core ||= CoreApiClient.new
    end
  end
end
