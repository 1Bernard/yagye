# frozen_string_literal: true

class DashboardController < ApplicationController
  def provider_split_breakdown
    authorize :dashboard, :index?
    provider_code = params[:provider_code].to_s
    return head :bad_request if provider_code.blank?

    scope     = payment_scope
    mtd_start = Time.current.beginning_of_month

    rows = scope
      .joins("LEFT JOIN portal_merchants ON portal_merchants.merchant_code = portal_payments.merchant_code")
      .where(provider: provider_code, status: "paid")
      .where("portal_payments.paid_at >= ?", mtd_start)
      .group("portal_payments.merchant_code, COALESCE(NULLIF(portal_merchants.trading_name, ''), portal_payments.merchant_code)")
      .select(
        "COALESCE(NULLIF(portal_merchants.trading_name, ''), portal_payments.merchant_code) AS merchant_name",
        "portal_payments.merchant_code",
        "SUM(portal_payments.amount) AS total_volume",
        "COUNT(portal_payments.id) AS tx_count"
      )
      .order("SUM(portal_payments.amount) DESC")
      .limit(10)

    total         = rows.sum { |r| r.total_volume.to_i }
    provider_name = Payment::PROVIDERS.fetch(provider_code, provider_code.humanize)
    color         = Payments::VolumeSummaryQuery::PROVIDER_COLORS.fetch(provider_code, "#9ca3af")

    render Dashboard::ProviderSplitDrawerView.new(
      provider_code: provider_code,
      provider_name: provider_name,
      color:         color,
      rows:          rows,
      total:         total
    )
  end

  def index
    authorize :dashboard, :index?
    scope      = payment_scope
    summary    = Payments::VolumeSummaryQuery.new(scope).call
    fx_currency = resolve_fx_currency
    cookies[:fx_currency] = fx_currency

    render Dashboard::IndexView.new(
      volume:             summary[:volume],
      prev_volume:        summary[:prev_volume],
      tx_count:           summary[:tx_count],
      prev_tx_count:      summary[:prev_tx_count],
      success_count:      summary[:success_count],
      success_rate:       summary[:success_rate],
      pending_count:      summary[:pending_count],
      failed_count:       summary[:failed_count],
      disputes_count:     disputes_count,
      kyb_pending_count:  current_user.internal_staff? ? kyb_pending_count : nil,
      active_merchant_count: current_user.internal_staff? ? active_merchant_count : nil,
      chart_dates:        summary[:chart_dates],
      chart_values:       summary[:chart_values],
      provider_data:      summary[:provider_data],
      method_data:        summary[:method_data],
      recent_payments:    scope.recent.limit(8),
      fx_currency:        fx_currency,
      fx_rate:            fetch_fx_rate(fx_currency),
      is_ops:             current_user.internal_staff?
    )
  end

  private

  FX_CURRENCIES = %w[GHS USD EUR GBP].freeze

  def resolve_fx_currency
    requested = params[:fx_currency].to_s.upcase
    return requested if FX_CURRENCIES.include?(requested)

    stored = cookies[:fx_currency].to_s.upcase
    return stored if FX_CURRENCIES.include?(stored)

    "GHS"
  end

  def fetch_fx_rate(currency)
    return nil if currency == "GHS"

    result = CoreApiClient.new.list_fx_rates
    return nil unless result.success?

    rates = result.body["data"] || []
    rates.find { |r| r["from_currency"] == "GHS" && r["to_currency"] == currency }
  rescue StandardError
    nil
  end

  def payment_scope
    current_user.internal_staff? ? Payment.all : Payment.for_merchant(current_user.merchant_code)
  end

  def disputes_count
    scope = current_user.internal_staff? ? Dispute.all : Dispute.for_merchant(current_user.merchant_code)
    scope.open.count
  rescue StandardError
    0
  end

  def kyb_pending_count
    PortalMerchantApplication.pending_review.count
  rescue StandardError
    0
  end

  def active_merchant_count
    Payment.where(status: "paid")
           .where("paid_at >= ?", Time.current.beginning_of_month)
           .distinct
           .count(:merchant_code)
  rescue StandardError
    0
  end
end
