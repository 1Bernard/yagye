# frozen_string_literal: true

module Payments
  class TransactionsController < ApplicationController
    def index
      authorize Payment, :index?
      scope = policy_scope(Payment)
      pagy, payments = pagy(Payments::TransactionsQuery.new(scope).call(filters), limit: 25)
      render Payments::IndexView.new(
        payments:      payments,
        pagy:          pagy,
        can_view_pii:  policy(Payment).view_customer_pii?,
        can_export:    policy(Payment).export?,
        status_filter: params[:status],
        method_filter: params[:method],
        from:          params[:from],
        to:            params[:to],
        query:         params[:q]
      )
    end

    def filter
      authorize Payment, :index?
      render Payments::FilterView.new(
        query:   params[:q],
        status:  params[:status],
        method:  params[:method],
        from:    params[:from],
        to:      params[:to]
      )
    end

    def show
      payment = decode_id(Payment)
      authorize payment

      events = []
      if payment.core_payment_id.present?
        result = CoreApiClient.new.get_payment_events(payment.core_payment_id)
        events = result.body["data"] || [] if result.success?
      end

      render Payments::ShowView.new(
        payment:      payment,
        events:       events,
        can_refund:   policy(payment).refund?,
        can_view_pii: policy(payment).view_customer_pii?
      )
    end

    def refund
      payment = decode_id(Payment)
      authorize payment, :refund?
      amount = params[:amount].present? ? params[:amount].to_i : payment.amount
      result = CoreApiClient.new.create_refund(
        payment.core_payment_id,
        amount: amount,
        reason:       params[:reason].to_s.strip.presence || "requested_by_merchant",
        initiated_by: current_user.user_code
      )
      if result.success?
        redirect_to payment_path(payment), notice: "Refund initiated."
      else
        redirect_to payment_path(payment), alert: result.error_message
      end
    end

    private

    def filters
      params.permit(:status, :q, :from, :to, :provider, :method).to_h.symbolize_keys
    end
  end
end
