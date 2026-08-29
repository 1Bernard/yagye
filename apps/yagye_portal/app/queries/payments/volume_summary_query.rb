# frozen_string_literal: true

module Payments
  # Computes all metrics needed by the dashboard in a single sweep.
  # Receives a policy-scoped relation so merchant vs. ops isolation is
  # enforced before any aggregation runs.
  class VolumeSummaryQuery
    PROVIDER_COLORS = {
      "mtn_momo"    => "#FFB800",
      "stripe"      => "#635bff",
      "paystack"    => "#00C3F7",
      "flutterwave" => "#F5A623"
    }.freeze

    CHART_DAYS = 30

    def initialize(relation = Payment.all)
      @relation = relation
    end

    def call
      @relation = @relation.where(mode: Current.mode) if Current.mode.present?

      now        = Time.current
      mtd_start  = now.beginning_of_month
      prev_start = mtd_start.prev_month
      prev_end   = prev_start + now.day.days

      paid     = @relation.where(status: "paid")
      mtd_paid = paid.where(paid_at: mtd_start..now)
      mtd_all  = @relation.where(created_at: mtd_start..now)
      prev_paid = paid.where(paid_at: prev_start...prev_end)
      prev_all  = @relation.where(created_at: prev_start...prev_end)

      window_start = CHART_DAYS.days.ago.to_date
      daily_sums   = paid
                       .where("paid_at >= ?", window_start.beginning_of_day)
                       .group("DATE(paid_at)")
                       .order("DATE(paid_at)")
                       .sum(:amount_cents)

      provider_totals = mtd_paid.group(:provider).sum(:amount_cents)
      total_vol       = provider_totals.values.sum.to_f

      success_count = mtd_paid.count
      tx_count      = mtd_all.count

      {
        volume_cents:      mtd_paid.sum(:amount_cents),
        prev_volume_cents: prev_paid.sum(:amount_cents),
        tx_count:          tx_count,
        prev_tx_count:     prev_all.count,
        success_count:     success_count,
        pending_count:     @relation.where(status: %w[initiated processing]).count,
        failed_count:      mtd_all.where(status: "failed").count,
        success_rate:      tx_count.positive? ? (success_count.to_f / tx_count * 100).round(1) : nil,
        chart_dates:       build_date_labels(window_start),
        chart_values:      build_chart_values(daily_sums, window_start),
        provider_data:     build_provider_data(provider_totals, total_vol)
      }
    end

    private

    def build_date_labels(from)
      (0...CHART_DAYS).map { |i| (from + i).strftime("%-d %b") }
    end

    def build_chart_values(daily_sums, from)
      (0...CHART_DAYS).map { |i| (daily_sums[from + i] || 0) / 100.0 }
    end

    def build_provider_data(provider_totals, total_vol)
      provider_totals.filter_map do |key, amt|
        next if key.blank?
        pct = total_vol.positive? ? (amt / total_vol * 100).round(1) : 0.0
        {
          key:          key.to_s,
          name:         Payment::PROVIDERS.fetch(key.to_s, key.to_s.humanize),
          amount_cents: amt,
          pct:          pct,
          color:        PROVIDER_COLORS.fetch(key.to_s, "#9ca3af")
        }
      end.sort_by { |p| -p[:amount_cents] }
    end
  end
end
