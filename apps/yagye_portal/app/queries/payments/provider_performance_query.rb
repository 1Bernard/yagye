# frozen_string_literal: true

module Payments
  # Cross-channel performance: success rate, volume, avg latency, fees.
  # "Terminal" here means a final dispatch outcome: paid (success) or
  # failed/cancelled/indeterminate (failure). Refunded and disputed are
  # excluded because they are merchant/customer actions on an already-succeeded
  # payment — including them in the denominator would understate true success rates.
  # Non-terminal statuses (created, processing, requires_action) are excluded so
  # in-flight payments don't skew the metric.
  class ProviderPerformanceQuery
    TERMINAL_STATUSES = %w[paid failed cancelled indeterminate].freeze

    Result = Data.define(
      :provider,
      :terminal_count,
      :succeeded_count,
      :failed_count,
      :success_rate,
      :gross_volume,
      :total_fees,
      :avg_latency_secs,
      :currency
    )

    def initialize(relation = Payment.all)
      @relation = relation
    end

    def call(from:, to:, currency: "GHS")
      rows = @relation
        .where(currency: currency)
        .where("created_at >= ? AND created_at <= ?", from, to)
        .where("provider IS NOT NULL AND provider != 'simulator'")
        .where(status: TERMINAL_STATUSES)
        .group(:provider)
        .select(
          "provider",
          "COUNT(*) AS terminal_count",
          "COUNT(*) FILTER (WHERE status = 'paid') AS succeeded_count",
          "COUNT(*) FILTER (WHERE status IN ('failed', 'cancelled', 'indeterminate')) AS failed_count",
          "COALESCE(SUM(amount) FILTER (WHERE status = 'paid'), 0) AS gross_volume",
          "COALESCE(SUM(fee_amount) FILTER (WHERE status = 'paid'), 0) AS total_fees",
          "ROUND(EXTRACT(EPOCH FROM AVG(paid_at - created_at) FILTER (WHERE status = 'paid' AND paid_at > created_at)))::bigint AS avg_latency_secs",
          "'#{sanitize_currency(currency)}'::text AS currency"
        )
        .order(Arel.sql("COALESCE(SUM(amount) FILTER (WHERE status = 'paid'), 0) DESC"))

      rows.map do |r|
        terminal = r.terminal_count.to_i
        succeeded = r.succeeded_count.to_i
        rate = terminal > 0 ? (succeeded.to_f / terminal * 100).round(1) : 0.0

        Result.new(
          provider:        r.provider,
          terminal_count:  terminal,
          succeeded_count: succeeded,
          failed_count:    r.failed_count.to_i,
          success_rate:    rate,
          gross_volume:    r.gross_volume.to_i,
          total_fees:      r.total_fees.to_i,
          avg_latency_secs: r.avg_latency_secs.to_i,
          currency:        r.currency
        )
      end
    end

    private

    def sanitize_currency(c)
      c.to_s.upcase.gsub(/[^A-Z]/, "")
    end
  end
end
