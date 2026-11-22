# frozen_string_literal: true

module Ai
  # Dispatches the 4 merchant analytics tools the LLM can call.
  # ALL queries are pre-scoped to the current merchant — the merchant_code
  # is set at construction time and never read from LLM input.
  class MerchantToolDispatcher
    PERIOD_RANGES = {
      "today" => -> { Time.current.beginning_of_day..Time.current },
      "7d"    => -> { 7.days.ago..Time.current },
      "mtd"   => -> { Time.current.beginning_of_month..Time.current },
      "30d"   => -> { 30.days.ago..Time.current }
    }.freeze

    def initialize(merchant_code:)
      @merchant_code = merchant_code
    end

    def dispatch(tool_name, input)
      case tool_name
      when "get_my_payment_volume"      then get_my_payment_volume(input)
      when "get_my_recent_payments"     then get_my_recent_payments(input)
      when "get_my_payout_balance"      then get_my_payout_balance
      when "get_my_settlement_batches"  then get_my_settlement_batches(input)
      when "get_my_customers"           then get_my_customers(input)
      when "get_my_refunds"             then get_my_refunds(input)
      else { error: "unknown tool: #{tool_name}" }
      end
    end

    def tool_definitions
      [
        {
          name: "get_my_payment_volume",
          description: "Returns this merchant's payment volume, transaction count, and success rate for a given period.",
          input_schema: {
            type: "object",
            properties: {
              period: { type: "string", enum: %w[today 7d mtd 30d],
                        description: "Time window. Defaults to mtd." }
            }
          }
        },
        {
          name: "get_my_recent_payments",
          description: "Returns this merchant's recent payments, optionally filtered by status.",
          input_schema: {
            type: "object",
            properties: {
              status: { type: "string",
                        description: "Filter by status: paid, failed, processing, initiated, refunded. Omit for all." },
              limit: { type: "integer", description: "Number of payments to return (1-25, default 10)." }
            }
          }
        },
        {
          name: "get_my_payout_balance",
          description: "Returns this merchant's accumulated net balance since the last completed payout, plus the next scheduled payout if one exists.",
          input_schema: { type: "object", properties: {} }
        },
        {
          name: "get_my_settlement_batches",
          description: "Returns this merchant's recent settlement batches with status and amounts.",
          input_schema: {
            type: "object",
            properties: {
              limit: { type: "integer", description: "Number of batches to return (1-10, default 5)." }
            }
          }
        },
        {
          name: "get_my_customers",
          description: "Returns this merchant's customer analytics: unique customer count, new customers this month, repeat rate, top spenders (amounts only, no personal data), and payment method breakdown.",
          input_schema: { type: "object", properties: {} }
        },
        {
          name: "get_my_refunds",
          description: "Returns this merchant's refund summary for a given period: count, total amount, and breakdown by payment method.",
          input_schema: {
            type: "object",
            properties: {
              period: { type: "string", enum: %w[today 7d mtd 30d],
                        description: "Time window. Defaults to mtd." }
            }
          }
        }
      ]
    end

    private

    def scoped_payments
      Payment.for_merchant(@merchant_code)
    end

    def get_my_payment_volume(input)
      period = input["period"] || "mtd"
      range  = PERIOD_RANGES.fetch(period, PERIOD_RANGES["mtd"]).call
      scope  = scoped_payments

      paid    = scope.where(status: %w[paid refunded], paid_at: range)
      all_in  = scope.where(created_at: range)
      count   = all_in.count
      success = paid.count

      # Group by currency — mixing GHS and USD minor units would give a meaningless total
      volume_by_currency = paid.group(:currency).sum(:amount)
                               .transform_values.with_index { |amt, _| amt.to_i }
                               .to_h

      {
        period:             period,
        volume_by_currency: volume_by_currency.map { |cur, amt| "#{cur}: #{format_amount(amt, cur)}" },
        tx_count:           count,
        success_count:      success,
        success_rate:       count.positive? ? "#{(success.to_f / count * 100).round(1)}%" : "n/a"
      }
    end

    def get_my_recent_payments(input)
      limit = (input["limit"] || 10).to_i.clamp(1, 25)
      scope = scoped_payments
      scope = scope.where(status: input["status"]) if input["status"].present?

      scope.order(created_at: :desc).limit(limit).map do |p|
        {
          id:         p.reference,
          amount:     format_amount(p.amount.to_i, p.currency),
          currency:   p.currency,
          status:     p.status,
          method:     p.payment_method,
          created_at: p.created_at&.strftime("%Y-%m-%d %H:%M UTC")
        }
      end
    end

    def get_my_payout_balance
      payout_scope = PortalPayout.for_merchant(@merchant_code)
      result = Payouts::BalanceSummaryQuery.new(scoped_payments, payout_scope).call
      return { accumulated_net: "GHS 0.00", payment_count: 0 } if result.nil?

      out = {
        accumulated_net:  format_amount(result[:balance].to_i),
        gross_collected:  format_amount(result[:gross].to_i),
        payment_count:    result[:payment_count],
        cycle_started_at: result[:cycle_start]&.strftime("%Y-%m-%d")
      }
      if result[:next_payout_date]
        out[:next_payout_date]   = result[:next_payout_date].strftime("%Y-%m-%d")
        out[:next_payout_amount] = format_amount(result[:next_payout_amount].to_i)
        out[:next_payout_state]  = result[:next_payout_state]
      end
      out
    end

    def get_my_settlement_batches(input)
      limit = (input["limit"] || 5).to_i.clamp(1, 10)
      core  = CoreApiClient.new
      result = core.list_settlement_batches(merchant_code: @merchant_code)
      return { error: "settlement data unavailable" } unless result.success?

      batches = Array(result.body["batches"] || result.body).first(limit)
      batches.map do |b|
        {
          id:         b["public_id"],
          status:     b["state"],
          net_amount: format_amount(b["total_net_minor"].to_i),
          created_at: b["created_at"]
        }
      end
    end

    def get_my_customers(*)
      scope      = scoped_payments
      month_start = Time.current.beginning_of_month

      # Unique customers by MSISDN (MoMo) or email (card/bank)
      msisdn_ids = scope.where.not(customer_msisdn: [ nil, "" ]).distinct.pluck(:customer_msisdn)
      email_ids  = scope.where(customer_msisdn: [ nil, "" ]).where.not(customer_email: [ nil, "" ])
                        .distinct.pluck(:customer_email)
      total_unique = (msisdn_ids + email_ids).uniq.size

      # New this month: first payment on record is within this month
      new_msisdn = scope.where(customer_msisdn: msisdn_ids)
                        .group(:customer_msisdn)
                        .having("MIN(created_at) >= ?", month_start)
                        .count.size
      new_email  = scope.where(customer_msisdn: [ nil, "" ]).where(customer_email: email_ids)
                        .group(:customer_email)
                        .having("MIN(created_at) >= ?", month_start)
                        .count.size
      new_this_month = new_msisdn + new_email

      # Top 5 customers by total paid amount — amounts only, no PII sent to LLM.
      # Group by customer AND currency to avoid summing GHS and USD minor units together.
      top_rows = scope.where(status: %w[paid refunded])
                      .group(Arel.sql(
                        "COALESCE(NULLIF(customer_msisdn,''), customer_email), currency"
                      ))
                      .select(Arel.sql(
                        "COALESCE(NULLIF(customer_msisdn,''), customer_email) AS ckey," \
                        "currency, SUM(amount) AS total_minor, COUNT(*) AS tx_count"
                      ))
                      .order("total_minor DESC")
                      .limit(10)

      top_spenders = top_rows.each_with_index.map do |r, i|
        {
          rank:         i + 1,
          total_spent:  format_amount(r.total_minor.to_i, r.currency),
          currency:     r.currency,
          transactions: r.tx_count.to_i
        }
      end

      # Method split
      by_method = scope.group(:payment_method).count

      {
        total_unique_customers: total_unique,
        new_this_month:         new_this_month,
        returning_customers:    total_unique - new_this_month,
        top_spenders:           top_spenders,
        by_payment_method:      by_method
      }
    end

    def get_my_refunds(input)
      period = input["period"] || "mtd"
      range  = PERIOD_RANGES.fetch(period, PERIOD_RANGES["mtd"]).call
      scope  = scoped_payments.where(status: "refunded", created_at: range)

      total_count        = scope.count
      total_by_currency  = scope.group(:currency).sum(:amount)
                               .map { |cur, amt| format_amount(amt.to_i, cur) }

      by_method = scope.group(:payment_method, :currency)
                       .select(:payment_method, :currency,
                               "COUNT(*) AS cnt", "SUM(amount) AS total_minor")
                       .map { |r| [ "#{r.payment_method}/#{r.currency}", { count: r.cnt.to_i, total: format_amount(r.total_minor.to_i, r.currency) } ] }
                       .to_h

      {
        period:            period,
        refund_count:      total_count,
        total_by_currency: total_by_currency,
        by_method:         by_method
      }
    end

    def format_amount(minor_units, currency = "GHS")
      cur = currency.to_s.upcase.presence || "GHS"
      return "#{cur} 0.00" if minor_units.nil? || minor_units.zero?
      "#{cur} #{format('%.2f', minor_units.to_f / 100)}"
    end
  end
end
