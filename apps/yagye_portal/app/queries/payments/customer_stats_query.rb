# frozen_string_literal: true

module Payments
  class CustomerStatsQuery
    def initialize(relation = Payment.all)
      @relation = relation
    end

    # Returns { msisdn => { payment_count:, refunded_count:, total_volume:,
    #                       last_payment_at:, first_payment_at:,
    #                       today_volume:, mtd_volume: } }
    def call(msisdns:)
      msisdns = Array(msisdns).compact.uniq
      return {} if msisdns.empty?

      conn        = ActiveRecord::Base.connection
      today_start = conn.quote(Time.current.beginning_of_day)
      month_start = conn.quote(Time.current.beginning_of_month)

      @relation
        .where(customer_msisdn: msisdns)
        .group(:customer_msisdn)
        .select(
          :customer_msisdn,
          "COUNT(*) AS payment_count",
          "COUNT(*) FILTER (WHERE status = 'refunded') AS refunded_count",
          "SUM(amount) AS total_volume",
          "MAX(created_at) AS last_payment_at",
          "MIN(created_at) AS first_payment_at",
          "COALESCE(SUM(amount) FILTER (WHERE status = 'paid' AND created_at >= #{today_start}), 0) AS today_volume",
          "COALESCE(SUM(amount) FILTER (WHERE status = 'paid' AND created_at >= #{month_start}), 0) AS mtd_volume"
        )
        .each_with_object({}) do |r, h|
          h[r.customer_msisdn] = {
            payment_count:    r.payment_count.to_i,
            refunded_count:   r.refunded_count.to_i,
            total_volume:     r.total_volume.to_i,
            last_payment_at:  r.last_payment_at,
            first_payment_at: r.first_payment_at,
            today_volume:     r.today_volume.to_i,
            mtd_volume:       r.mtd_volume.to_i
          }
        end
    end

    # Returns { msisdn => provider_code } — the provider with the most paid transactions
    def primary_networks(msisdns:)
      msisdns = Array(msisdns).compact.uniq
      return {} if msisdns.empty?

      rows = @relation
        .where(customer_msisdn: msisdns, status: "paid")
        .group(:customer_msisdn, :provider)
        .select(:customer_msisdn, :provider, "COUNT(*) AS cnt")
        .order("customer_msisdn, cnt DESC")

      rows.each_with_object({}) do |r, h|
        h[r.customer_msisdn] ||= r.provider
      end
    end
  end
end
