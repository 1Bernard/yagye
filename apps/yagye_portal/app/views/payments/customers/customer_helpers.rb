# frozen_string_literal: true

module Payments
  module Customers
    module CustomerHelpers
      HIGH_VALUE_THRESHOLD_CENTS = 100_000   # GHS 1,000
      NEW_WINDOW_DAYS            = 30
      CHURN_WINDOW_DAYS          = 90

      # BoG MoMo velocity limits (minor units = pesewas)
      VELOCITY_LIMITS = {
        "tier_1" => { daily: 100_000,   monthly: 500_000   },  # GHS 1k / GHS 5k
        "tier_2" => { daily: 500_000,   monthly: 3_000_000  },  # GHS 5k / GHS 30k
        "tier_3" => { daily: 2_000_000, monthly: 20_000_000 }   # GHS 20k / GHS 200k
      }.freeze

      # Returns array of symbols: :new, :high_value, :churned
      def customer_segments(stat)
        return [] unless stat
        segs = []
        segs << :new        if stat[:first_payment_at] && stat[:first_payment_at] >= NEW_WINDOW_DAYS.days.ago
        segs << :high_value if stat[:total_volume].to_i >= HIGH_VALUE_THRESHOLD_CENTS
        segs << :churned    if stat[:last_payment_at] && stat[:last_payment_at] < CHURN_WINDOW_DAYS.days.ago
        segs
      end

      # Returns :ok, :near_limit, :at_limit, or :unknown
      def velocity_status(stat, kyc_tier)
        return :unknown unless stat
        limits = VELOCITY_LIMITS[kyc_tier.to_s]
        return :unknown unless limits

        daily_pct   = stat[:today_volume].to_f / limits[:daily]
        monthly_pct = stat[:mtd_volume].to_f   / limits[:monthly]

        case [daily_pct, monthly_pct].max
        when (1.0..)  then :at_limit
        when (0.8..)  then :near_limit
        else               :ok
        end
      end

      def velocity_limits_for(kyc_tier)
        VELOCITY_LIMITS[kyc_tier.to_s]
      end
    end
  end
end
