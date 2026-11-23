# frozen_string_literal: true

module Payments
  # Summarises Yagye platform fees per provider for a given merchant + date range.
  # Only considers paid payments that have a non-zero fee_amount.
  # Source: portal_payments (fee_amount synced from Core on payment.succeeded event).
  class FeeStatementQuery
    Result = Data.define(:provider, :tx_count, :gross_volume, :net_volume, :total_fees, :currency)

    def initialize(relation = Payment.all)
      @relation = relation
    end

    def call(from:, to:, currency: "GHS")
      rows = @relation
        .where(status: "paid", currency: currency)
        .where("paid_at >= ? AND paid_at <= ?", from, to)
        .where("fee_amount IS NOT NULL AND fee_amount > 0")
        .where("provider IS NOT NULL")
        .group(:provider)
        .select(
          "provider",
          "COUNT(*) AS tx_count",
          "SUM(amount) AS gross_volume",
          "SUM(COALESCE(net_amount, amount - fee_amount)) AS net_volume",
          "SUM(fee_amount) AS total_fees",
          "'#{sanitize_currency(currency)}'::text AS currency"
        )
        .order(Arel.sql("SUM(fee_amount) DESC"))

      rows.map do |r|
        Result.new(
          provider:    r.provider,
          tx_count:    r.tx_count.to_i,
          gross_volume: r.gross_volume.to_i,
          net_volume:  r.net_volume.to_i,
          total_fees:  r.total_fees.to_i,
          currency:    r.currency
        )
      end
    end

    private

    def sanitize_currency(c)
      c.to_s.upcase.gsub(/[^A-Z]/, "")
    end
  end
end
