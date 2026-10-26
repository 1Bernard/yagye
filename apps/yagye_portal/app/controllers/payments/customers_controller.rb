# frozen_string_literal: true

module Payments
  class CustomersController < ApplicationController
    def index
      authorize :customer, :index?, policy_class: CustomerPolicy
      result    = core.list_customers(merchant_code: current_user.merchant_code)
      customers = result.success? ? (result.body["data"] || []) : []
      customers = filter_customers(customers)

      # merchant_customer_ref is the MoMo MSISDN for mobile-money customers —
      # the same value stored as payment.customer_msisdn. c["msisdn"] is the
      # separately-collected contact phone, which can differ.
      msisdns  = customers.filter_map { |c| c["merchant_customer_ref"] }.uniq
      query    = Payments::CustomerStatsQuery.new(payment_scope)
      stats    = query.call(msisdns: msisdns)
      networks = query.primary_networks(msisdns: msisdns)

      render Payments::Customers::IndexView.new(
        customers: customers,
        query:     params[:q],
        stats:     stats,
        networks:  networks
      )
    end

    def show
      authorize :customer, :show?, policy_class: CustomerPolicy
      result = core.get_customer(params[:id])
      return redirect_to(customers_path, alert: "Customer not found.") unless result.success?

      customer = result.body
      momo     = customer["merchant_customer_ref"]
      query    = Payments::CustomerStatsQuery.new(payment_scope)
      stat     = momo.present? ? query.call(msisdns: [ momo ])[momo] : nil
      network  = momo.present? ? query.primary_networks(msisdns: [ momo ])[momo] : nil

      render Payments::Customers::ShowView.new(customer: customer, stat: stat, network: network)
    end

    private

    def payment_scope
      current_user.internal_staff? ? Payment.all : Payment.for_merchant(current_user.merchant_code)
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
