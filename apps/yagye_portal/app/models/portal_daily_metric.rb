# frozen_string_literal: true

class PortalDailyMetric < ApplicationRecord
  self.primary_key = [ :merchant_code, :day, :currency, :mode ]

  validates :merchant_code, :day, :currency, :mode, presence: true

  # Recomputes metrics for a given (merchant, day, currency, mode) combination.
  # gross_volume is keyed on paid_at to match the dashboard chart (GROUP BY DATE(paid_at)).
  # payment_count / failed_count are keyed on created_at (initiated on this day).
  # Idempotent: safe to call repeatedly.
  def self.recompute_for!(merchant_code:, day:, currency:, mode:)
    base = Payment.where(merchant_code: merchant_code, currency: currency, mode: mode)

    paid_scope      = base.where(status: "paid").where("DATE(paid_at) = ?", day)
    gross_volume    = paid_scope.sum(:amount)
    succeeded_count = paid_scope.count

    refund_scope  = base.where(status: "refunded").where("DATE(updated_at) = ?", day)
    refund_volume = refund_scope.sum(:amount)

    created_scope    = base.where("DATE(created_at) = ?", day)
    payment_count    = created_scope.count
    failed_count     = created_scope.where(status: "failed").count
    chargeback_count = created_scope.where(status: "disputed").count

    attrs = {
      merchant_code:    merchant_code,
      day:              day,
      currency:         currency,
      mode:             mode,
      payment_count:    payment_count,
      succeeded_count:  succeeded_count,
      failed_count:     failed_count,
      gross_volume:     gross_volume,
      refund_volume:    refund_volume,
      chargeback_count: chargeback_count
    }

    upsert(attrs, unique_by: [ :merchant_code, :day, :currency, :mode ])
  end

  # Recomputes for all active (merchant, currency, mode) combinations for a given day.
  # Covers both payments created and payments paid on that day.
  def self.recompute_all_for_day!(day)
    combos = Payment
      .where("DATE(created_at) = ? OR DATE(paid_at) = ?", day, day)
      .select(:merchant_code, :currency, :mode)
      .distinct

    combos.each do |combo|
      recompute_for!(
        merchant_code: combo.merchant_code,
        day:           day,
        currency:      combo.currency,
        mode:          combo.mode
      )
    end
  end
end
