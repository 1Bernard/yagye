# frozen_string_literal: true

module Payments
  # Computes per-rail success rate from terminal-state portal_payments in the
  # last 30 minutes. Pure DB query — no telco API calls needed.
  #
  # Status thresholds:  >= 90% → :healthy   >= 70% → :degraded   < 70% → :disrupted
  # Minimum sample:     < 5 terminal payments in window → :no_data
  class NetworkHealthQuery
    WINDOW_MINUTES = 30
    MIN_SAMPLE     = 5

    PROVIDERS = [
      { key: "mtn_momo",     name: "MTN MoMo",        color: "#FFCC00" },
      { key: "telecel_cash", name: "Telecel Cash",     color: "#E2001A" },
      { key: "airteltigo",   name: "AirtelTigo Money", color: "#FF6B00" },
    ].freeze

    TERMINAL = %w[paid failed cancelled indeterminate].freeze

    def initialize(relation = Payment.all)
      @relation = relation
    end

    def call
      @relation = @relation.where(mode: Current.mode) if Current.mode.present?

      provider_keys = PROVIDERS.map { |p| p[:key] }

      rows = @relation
               .where(status: TERMINAL, provider: provider_keys)
               .where("created_at >= ?", WINDOW_MINUTES.minutes.ago)
               .group(:provider)
               .select(
                 :provider,
                 "COUNT(*) AS total_count",
                 "SUM(CASE WHEN status = 'paid' THEN 1 ELSE 0 END) AS paid_count"
               )

      mtd_failed = @relation
                     .where(status: %w[failed cancelled], provider: provider_keys)
                     .where("created_at >= ?", Time.current.beginning_of_month)
                     .group(:provider)
                     .sum(:amount)

      by_provider = rows.each_with_object({}) do |r, h|
        h[r.provider] = { total: r.total_count.to_i, paid: r.paid_count.to_i }
      end

      PROVIDERS.map { |meta| build_entry(meta, by_provider[meta[:key]], mtd_failed[meta[:key]].to_i) }
    end

    private

    def build_entry(meta, counts, failed_volume_mtd)
      total = counts&.fetch(:total, 0).to_i
      paid  = counts&.fetch(:paid, 0).to_i

      if total < MIN_SAMPLE
        meta.merge(status: :no_data, rate: nil, total: total, failed_volume_mtd: failed_volume_mtd)
      else
        rate   = (paid.to_f / total * 100).round(1)
        status = rate >= 90 ? :healthy : rate >= 70 ? :degraded : :disrupted
        meta.merge(status: status, rate: rate, total: total, failed_volume_mtd: failed_volume_mtd)
      end
    end
  end
end
