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
      rows = currency_rows(:customer_msisdn, msisdns)
      merge_currency_rows(rows, :customer_msisdn)
    end

    def stats_by_email(emails)
      rows = currency_rows(:customer_email, emails)
      merge_currency_rows(rows, :customer_email)
    end

    # Queries grouped by (ref_field, currency) so volumes stay per-currency.
    def currency_rows(ref_field, refs)
      conn        = ActiveRecord::Base.connection
      today_start = conn.quote(Time.current.beginning_of_day)
      month_start = conn.quote(Time.current.beginning_of_month)

      @relation
        .where(ref_field => refs)
        .group(ref_field, :currency)
        .select(
          ref_field,
          :currency,
          "COUNT(*) AS payment_count",
          "COUNT(*) FILTER (WHERE status = 'refunded') AS refunded_count",
          "SUM(amount) AS total_volume",
          "MAX(created_at) AS last_payment_at",
          "MIN(created_at) AS first_payment_at",
          "COALESCE(SUM(amount) FILTER (WHERE status = 'paid' AND created_at >= #{today_start}), 0) AS today_volume",
          "COALESCE(SUM(amount) FILTER (WHERE status = 'paid' AND created_at >= #{month_start}), 0) AS mtd_volume"
        )
        .to_a
    end

    # Merges per-(ref, currency) rows into { ref => stats } where volumes are
    # broken out per currency: volumes: {"GHS" => x, "USD" => y}.
    # payment_count and timestamps are aggregated across all currencies.
    def merge_currency_rows(rows, ref_field)
      rows.each_with_object({}) do |r, h|
        ref = r.public_send(ref_field)
        cur = r.currency.to_s.upcase

        h[ref] ||= {
          payment_count:    0,
          refunded_count:   0,
          volumes:          {},
          mtd_volumes:      {},
          today_volumes:    {},
          last_payment_at:  nil,
          first_payment_at: nil
        }

        h[ref][:payment_count]  += r.payment_count.to_i
        h[ref][:refunded_count] += r.refunded_count.to_i
        h[ref][:volumes][cur]        = r.total_volume.to_i
        h[ref][:mtd_volumes][cur]    = r.mtd_volume.to_i
        h[ref][:today_volumes][cur]  = r.today_volume.to_i
        h[ref][:last_payment_at]  = [ h[ref][:last_payment_at],  r.last_payment_at ].compact.max
        h[ref][:first_payment_at] = [ h[ref][:first_payment_at], r.first_payment_at ].compact.min
      end
    end
  end
end
