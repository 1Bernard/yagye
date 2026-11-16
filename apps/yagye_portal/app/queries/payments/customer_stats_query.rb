# frozen_string_literal: true

module Payments
  class CustomerStatsQuery
    def initialize(relation = Payment.all)
      @relation = relation
    end

    # Returns { ref => stats_hash } keyed by merchant_customer_ref (MSISDN or email).
    # Handles both mobile-money customers (looked up by customer_msisdn) and
    # card/bank-transfer customers (looked up by customer_email).
    def call(refs:)
      refs = Array(refs).compact.uniq
      return {} if refs.empty?

      msisdns, emails = refs.partition { |r| r.exclude?("@") }

      msisdn_stats = msisdns.any? ? stats_by_msisdn(msisdns) : {}
      email_stats  = emails.any?  ? stats_by_email(emails)   : {}

      msisdn_stats.merge(email_stats)
    end

    # Returns { ref => provider_code } — the provider with the most paid transactions.
    def primary_networks(refs:)
      refs = Array(refs).compact.uniq
      return {} if refs.empty?

      msisdns, _emails = refs.partition { |r| r.exclude?("@") }
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

    private

    def stats_by_msisdn(msisdns)
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
        .each_with_object({}) { |r, h| h[r.customer_msisdn] = row_to_stats(r) }
    end

    def stats_by_email(emails)
      conn        = ActiveRecord::Base.connection
      today_start = conn.quote(Time.current.beginning_of_day)
      month_start = conn.quote(Time.current.beginning_of_month)

      @relation
        .where(customer_email: emails)
        .group(:customer_email)
        .select(
          :customer_email,
          "COUNT(*) AS payment_count",
          "COUNT(*) FILTER (WHERE status = 'refunded') AS refunded_count",
          "SUM(amount) AS total_volume",
          "MAX(created_at) AS last_payment_at",
          "MIN(created_at) AS first_payment_at",
          "COALESCE(SUM(amount) FILTER (WHERE status = 'paid' AND created_at >= #{today_start}), 0) AS today_volume",
          "COALESCE(SUM(amount) FILTER (WHERE status = 'paid' AND created_at >= #{month_start}), 0) AS mtd_volume"
        )
        .each_with_object({}) { |r, h| h[r.customer_email] = row_to_stats(r) }
    end

    def row_to_stats(r)
      {
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
end
