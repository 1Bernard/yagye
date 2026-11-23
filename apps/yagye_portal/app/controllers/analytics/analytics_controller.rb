# frozen_string_literal: true

module Analytics
  class AnalyticsController < ApplicationController
    SUPPORTED_CURRENCIES = %w[GHS USD EUR GBP].freeze
    DEFAULT_DAYS = 30

    def fee_statement
      authorize :analytics, :view?
      from, to   = resolve_date_range
      currency   = resolve_currency
      rows       = Payments::FeeStatementQuery.new(payment_scope).call(from: from, to: to, currency: currency)
      total_fees = rows.sum(&:total_fees)

      render Analytics::FeeStatementView.new(
        rows:       rows,
        total_fees: total_fees,
        from:       from,
        to:         to,
        currency:   currency
      )
    end

    def provider_performance
      authorize :analytics, :view?
      from, to = resolve_date_range
      currency = resolve_currency
      rows     = Payments::ProviderPerformanceQuery.new(payment_scope).call(from: from, to: to, currency: currency)

      render Analytics::ProviderPerformanceView.new(
        rows:     rows,
        from:     from,
        to:       to,
        currency: currency
      )
    end

    private

    def payment_scope
      if current_user.internal_staff?
        Payment.where(mode: "live")
      else
        Payment.for_merchant(current_user.merchant_code)
               .for_portal_mode(Current.mode || "live")
      end
    end

    def resolve_date_range
      from = parse_date(params[:from]) || DEFAULT_DAYS.days.ago.beginning_of_day
      to   = parse_date(params[:to])   || Time.current.end_of_day
      [ from, to ]
    end

    def resolve_currency
      c = params[:currency].to_s.upcase
      SUPPORTED_CURRENCIES.include?(c) ? c : "GHS"
    end

    def parse_date(val)
      return nil if val.blank?
      Time.zone.parse(val.to_s)
    rescue ArgumentError
      nil
    end
  end
end
