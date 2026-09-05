# frozen_string_literal: true

module Payments
  class TransactionsController < ApplicationController
    def index
      authorize Payment, :index?
      scope = policy_scope(Payment)
      pagy, payments = pagy(Payments::TransactionsQuery.new(scope).call(filters), limit: 25)
      render Payments::IndexView.new(
        payments: payments, pagy: pagy,
        can_view_pii: policy(Payment).view_customer_pii?,
        can_export:   policy(Payment).export?,
        status_filter: params[:status], query: params[:q]
      )
    end

    def show
      payment = decode_id(Payment)
      authorize payment
      render Payments::ShowView.new(
        payment: payment,
        can_refund:   policy(payment).refund?,
        can_view_pii: policy(payment).view_customer_pii?
      )
    end

    def refund
      payment = decode_id(Payment)
      authorize payment, :refund?
      amount_cents = params[:amount_cents].present? ? params[:amount_cents].to_i : payment.amount_cents
      result = CoreApiClient.new.create_refund(
        payment.core_payment_id,
        amount_cents: amount_cents,
        reason:       params[:reason].to_s.strip.presence || "requested_by_merchant",
        initiated_by: current_user.email
      )
      if result.success?
        redirect_to payment_path(payment), notice: "Refund initiated."
      else
        redirect_to payment_path(payment), alert: result.error_message
      end
    end

    private

    def filters
      params.permit(:status, :q, :from, :to, :provider).to_h.symbolize_keys
    end
  end
end
