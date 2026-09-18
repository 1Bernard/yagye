# frozen_string_literal: true

module Payments
  class CustomersController < ApplicationController
    def index
      authorize :customer, :index?, policy_class: CustomerPolicy
      result    = core.list_customers(merchant_code: current_user.merchant_code)
      customers = result.success? ? (result.body["data"] || []) : []
      customers = filter_customers(customers)
      render Payments::Customers::IndexView.new(customers: customers, query: params[:q])
    end

    def show
      authorize :customer, :show?, policy_class: CustomerPolicy
      result = core.get_customer(params[:id])
      return redirect_to(customers_path, alert: "Customer not found.") unless result.success?

      customer = result.body
      render Payments::Customers::ShowView.new(customer: customer)
    end

    private

    def filter_customers(customers)
      return customers if params[:q].blank?

      q = params[:q].to_s.downcase
      customers.select do |c|
        c["merchant_customer_ref"].to_s.downcase.include?(q) ||
          c["id"].to_s.downcase.include?(q)
      end
    end

    def core
      @core ||= CoreApiClient.new
    end
  end
end
