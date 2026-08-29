# frozen_string_literal: true

module Payments
  class TransactionsController < ApplicationController
    def index
      authorize Payment, :index?
      scope = policy_scope(Payment)
      pagy, payments = pagy(Payments::TransactionsQuery.new(scope).call(filters), limit: 25)
      render Payments::IndexPage.new(
        payments: payments, pagy: pagy,
        can_view_pii: policy(Payment).view_customer_pii?,
        can_export:   policy(Payment).export?,
        status_filter: params[:status], query: params[:q]
      )
    end

    def show
      payment = policy_scope(Payment).find(params[:id])
      authorize payment
      render Payments::ShowPage.new(
        payment: payment,
        can_refund:   policy(payment).refund?,
        can_view_pii: policy(payment).view_customer_pii?
      )
    end

    private

    def filters
      params.permit(:status, :q, :from, :to, :provider).to_h.symbolize_keys
    end
  end
end
