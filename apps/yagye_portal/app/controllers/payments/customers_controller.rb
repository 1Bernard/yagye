# frozen_string_literal: true

module Payments
  class CustomersController < ApplicationController
    def index
      authorize :customer, :index?, policy_class: CustomerPolicy

      if current_user.internal_staff?
        redirect_to merchants_path,
          alert: "Select a merchant to view their customers."
        return
      end

      result    = core.list_customers(merchant_code: current_user.merchant_code)
      customers = result.success? ? (result.body["data"] || []) : []
      customers = filter_customers(customers)

      # merchant_customer_ref is the MoMo MSISDN for mobile-money customers —
      # the same value stored as payment.customer_msisdn. c["msisdn"] is the
      # separately-collected contact phone, which can differ.
      refs     = customers.filter_map { |c| c["merchant_customer_ref"] }.uniq
      query    = Payments::CustomerStatsQuery.new(payment_scope)
      stats    = query.call(refs: refs)
      networks = query.primary_networks(refs: refs)

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
      ref      = customer["merchant_customer_ref"]
      query    = Payments::CustomerStatsQuery.new(payment_scope)
      stat     = ref.present? ? query.call(refs: [ ref ])[ref] : nil
      network  = ref.present? ? query.primary_networks(refs: [ ref ])[ref] : nil

      render Payments::Customers::ShowView.new(customer: customer, stat: stat, network: network)
    end

    private

    def payment_scope
      current_user.internal_staff? ? Payment.all : Payment.for_merchant(current_user.merchant_code)
    end

    def customers_from_payments
      seen = {}
      payment_scope
        .where("(customer_email IS NOT NULL AND customer_email <> '') OR (customer_msisdn IS NOT NULL AND customer_msisdn <> '')")
        .select(:customer_email, :customer_msisdn)
        .order(created_at: :desc)
        .each_with_object([]) do |p, arr|
          ref = p.customer_email.presence || p.customer_msisdn.presence
          next unless ref
          next if seen.key?(ref)
          seen[ref] = true
          arr << {
            "id"                    => nil,
            "object"                => "customer",
            "merchant_customer_ref" => ref,
            "name"                  => nil,
            "email"                 => p.customer_email.presence,
            "msisdn"                => p.customer_msisdn.presence,
            "kyc_tier"              => "tier_1",
            "kyc_verified_at"       => nil,
            "inserted_at"           => nil
          }
        end
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

