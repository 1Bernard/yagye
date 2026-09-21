# frozen_string_literal: true

module Payments
  class TransactionsController < ApplicationController
    def index
      authorize Payment, :index?
      base_scope = policy_scope(Payment)
      is_ops     = current_user.internal_staff?

      query_scope = if is_ops
        base_scope
          .joins("LEFT JOIN portal_merchants ON portal_merchants.merchant_code = portal_payments.merchant_code")
          .select("portal_payments.*, COALESCE(NULLIF(portal_merchants.trading_name, ''), portal_payments.merchant_code) AS merchant_name")
      else
        base_scope
      end

      pagy, payments = pagy(Payments::TransactionsQuery.new(query_scope).call(filters), limit: 25)

      render Payments::IndexView.new(
        payments:      payments,
        pagy:          pagy,
        stats:         payment_stats(base_scope),
        show_merchant: is_ops,
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

    def payment_stats(scope)
      mtd_start = Time.current.beginning_of_month
      paid_mtd   = scope.where(status: "paid").where("paid_at >= ?", mtd_start)
      {
        volume_mtd:       paid_mtd.sum(:amount),
        volume_currency:  scope.pick(:currency) || "GHS",
        transactions_mtd: paid_mtd.count,
        pending:          scope.where(status: %w[created processing requires_action]).count,
        failed:           scope.where(status: %w[failed cancelled]).count
      }
    end
  end
end
