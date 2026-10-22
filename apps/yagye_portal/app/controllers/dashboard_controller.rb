# frozen_string_literal: true

class DashboardController < ApplicationController
  def provider_split_breakdown
    authorize :dashboard, :index?
    provider_code = params[:provider_code].to_s
    return head :bad_request if provider_code.blank?

    rows = Payments::ProviderSplitQuery.new(payment_scope).call(provider_code: provider_code)

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
    scope        = payment_scope
    summary      = Payments::VolumeSummaryQuery.new(scope).call
    fx_currency  = resolve_fx_currency
    fx_corridor  = fetch_corridor_rates
    cookies[:fx_currency] = fx_currency

    chart = merchant_chart_data || { dates: summary[:chart_dates], values: summary[:chart_values] }

    render Dashboard::IndexView.new(
      volume:             summary[:volume],
      net_volume:         summary[:net_volume],
      refunded_volume:    summary[:refunded_volume],
      refunded_count:     summary[:refunded_count],
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
      chart_dates:        chart[:dates],
      chart_values:       chart[:values],
      provider_data:      summary[:provider_data],
      method_data:        summary[:method_data],
      recent_payments:    scope.recent.limit(8),
      fx_currency:        fx_currency,
      fx_rate:            fx_corridor.find { |r| r[:currency] == fx_currency },
      fx_corridor:        fx_corridor,
      is_ops:             current_user.internal_staff?,
      network_health:     network_health_data(scope),
      upcoming_payout:    upcoming_payout_data,
      payout_balance:     payout_balance_data,
      wallet_balance:     wallet_balance_data,
      feed_stream_key:    merchant_feed_stream_key
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

  def fetch_corridor_rates
    result = CoreApiClient.new.list_fx_rates
    return [] unless result.success?

    (result.body["data"] || [])
      .select { |r| r["base"] == "GHS" }
      .map { |r| { currency: r["quote"], rate: r["rate"].to_f } }
  rescue StandardError
    []
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

  def network_health_data(scope)
    Payments::NetworkHealthQuery.new(scope).call
  rescue StandardError
    []
  end

  def upcoming_payout_data
    payout_rel = current_user.internal_staff? ? PortalPayout.all : PortalPayout.for_merchant(current_user.merchant_code)
    Payouts::UpcomingPayoutQuery.new(payout_rel, is_ops: current_user.internal_staff?).call
  rescue StandardError
    nil
  end

  def payout_balance_data
    return nil if current_user.internal_staff?
    code       = current_user.merchant_code
    Payouts::BalanceSummaryQuery.new(
      Payment.for_merchant(code),
      PortalPayout.for_merchant(code)
    ).call
  rescue StandardError
    nil
  end

  def merchant_feed_stream_key
    return nil if current_user.internal_staff?
    mode = Current.mode.presence || "live"
    "dashboard_feed_#{current_user.merchant_code}_#{mode}"
  end

  # Returns pre-aggregated chart data from portal_daily_metrics when available.
  # Falls back to nil so the caller uses VolumeSummaryQuery's live aggregation.
  def merchant_chart_data
    return nil if current_user.internal_staff?

    code  = current_user.merchant_code
    mode  = Current.mode.presence || "live"
    from  = Payments::VolumeSummaryQuery::CHART_DAYS.days.ago.to_date
    rows  = PortalDailyMetric.where(merchant_code: code, mode: mode)
                              .where(day: from..)
                              .order(:day)
    return nil unless rows.any?

    by_day = rows.group_by(&:day)
    days   = Payments::VolumeSummaryQuery::CHART_DAYS
    dates  = (0...days).map { |i| (from + i).strftime("%-d %b") }
    values = (0...days).map { |i| (by_day[from + i]&.first&.gross_volume || 0) / 100.0 }
    { dates: dates, values: values }
  rescue StandardError
    nil
  end

  def wallet_balance_data
    return nil if current_user.internal_staff?

    code = current_user.merchant_code
    mode = Current.mode.presence || "live"
    rows = PortalMerchantBalance.for_merchant(code, mode: mode).to_a
    return nil if rows.empty?

    currency  = rows.first.currency
    available = rows.sum(&:available)
    pending   = rows.sum(&:pending)
    in_transit = rows.sum(&:in_transit)
    reserved  = rows.sum(&:reserved)
    return nil if (available + pending + in_transit + reserved).zero?

    { available: available, pending: pending, in_transit: in_transit,
      reserved: reserved, currency: currency }
  rescue StandardError
    nil
  end
end
