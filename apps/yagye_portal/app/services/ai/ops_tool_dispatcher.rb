# frozen_string_literal: true

module Ai
  # Dispatches the 8 ops analytics tools the LLM can call.
  # All queries run against Payment.where(mode: "live") — no merchant scoping.
  # Only called by OpsChat — Pundit enforces internal_staff? before this runs.
  class OpsToolDispatcher
    PERIOD_RANGES = {
      "today" => -> { Time.current.beginning_of_day..Time.current },
      "7d"    => -> { 7.days.ago..Time.current },
      "mtd"   => -> { Time.current.beginning_of_month..Time.current },
      "30d"   => -> { 30.days.ago..Time.current }
    }.freeze

    def dispatch(tool_name, input)
      case tool_name
      when "get_payment_volume"        then get_payment_volume(input)
      when "get_provider_health"       then get_provider_health(input)
      when "get_flagged_payments"      then get_flagged_payments(input)
      when "get_settlement_pipeline"   then get_settlement_pipeline
      when "get_merchant_payables"     then get_merchant_payables
      when "get_provider_breakdown"    then get_provider_breakdown(input)
      when "get_dispute_summary"       then get_dispute_summary(input)
      when "get_reconciliation_health" then get_reconciliation_health
      when "get_merchant_stats"        then get_merchant_stats(input)
      when "get_kyb_queue"             then get_kyb_queue
      else { error: "unknown tool: #{tool_name}" }
      end
    end

    def tool_definitions
      [
        {
          name: "get_payment_volume",
          description: "Returns payment volume, transaction count, and success rate for a given period.",
          input_schema: {
            type: "object",
            properties: {
              period: { type: "string", enum: %w[today 7d mtd 30d],
                        description: "Time window. Defaults to mtd." }
            }
          }
        },
        {
          name: "get_provider_health",
          description: "Returns 30-minute success rate and health status (healthy/degraded/disrupted) for each MoMo provider. Pass provider_code to filter to one provider.",
          input_schema: {
            type: "object",
            properties: {
              provider_code: { type: "string",
                               description: "Optional. One of: mtn_momo, telecel_cash, airteltigo" }
            }
          }
        },
        {
          name: "get_flagged_payments",
          description: "Returns count and recent cases of risk-flagged payments awaiting disposition.",
          input_schema: {
            type: "object",
            properties: {
              decision: { type: "string", enum: %w[review block],
                          description: "Filter by risk_decision. Omit for all flagged." },
              limit: { type: "integer", description: "Max cases to return (default 10)." }
            }
          }
        },
        {
          name: "get_settlement_pipeline",
          description: "Returns settlement batch counts by state (pending, approved, dispatched, failed) and the last 5 failed disbursements.",
          input_schema: { type: "object", properties: {} }
        },
        {
          name: "get_merchant_payables",
          description: "Returns the top merchants ranked by outstanding payable amount.",
          input_schema: { type: "object", properties: {} }
        },
        {
          name: "get_provider_breakdown",
          description: "Returns per-provider transaction volume and percentage share for a given period.",
          input_schema: {
            type: "object",
            properties: {
              period: { type: "string", enum: %w[today 7d mtd 30d],
                        description: "Time window. Defaults to mtd." }
            }
          }
        },
        {
          name: "get_dispute_summary",
          description: "Returns dispute counts grouped by status.",
          input_schema: {
            type: "object",
            properties: {
              status: { type: "string",
                        description: "Filter by status (open, won, lost, pending). Omit for all." }
            }
          }
        },
        {
          name: "get_reconciliation_health",
          description: "Returns today's reconciliation match rate and unmatched/disputed counts.",
          input_schema: { type: "object", properties: {} }
        },
        {
          name: "get_merchant_stats",
          description: "Returns payment volume, success rate, and account status for a specific merchant. Use when asked about a named merchant or merchant code.",
          input_schema: {
            type: "object",
            required: [ "merchant_code" ],
            properties: {
              merchant_code: { type: "string", description: "The merchant's code (e.g. MCH001)." },
              period: { type: "string", enum: %w[today 7d mtd 30d],
                        description: "Time window for volume stats. Defaults to mtd." }
            }
          }
        },
        {
          name: "get_kyb_queue",
          description: "Returns the KYB (Know Your Business) application queue: pending count by status and the 5 most recent pending applications.",
          input_schema: { type: "object", properties: {} }
        }
      ]
    end

    private

    def live_payments
      Payment.where(mode: "live")
    end

    def get_payment_volume(input)
      period  = input["period"] || "mtd"
      range   = PERIOD_RANGES.fetch(period, PERIOD_RANGES["mtd"]).call
      scope   = live_payments

      paid    = scope.where(status: %w[paid refunded], paid_at: range)
      all_in  = scope.where(created_at: range)
      count   = all_in.count
      success = paid.count

      volume_by_currency = paid.group(:currency).sum(:amount)
                               .map { |cur, amt| "#{cur}: #{format_amount(amt.to_i, cur)}" }

      {
        period:             period,
        volume_by_currency: volume_by_currency,
        tx_count:           count,
        success_count:      success,
        success_rate:       count.positive? ? "#{(success.to_f / count * 100).round(1)}%" : "n/a"
      }
    end

    def get_provider_health(input)
      rows = Payments::NetworkHealthQuery.new(live_payments).call
      if (code = input["provider_code"].presence)
        rows = rows.select { |r| r[:key] == code }
      end
      rows.map { |r| r.slice(:key, :name, :status, :rate, :total) }
    end

    def get_flagged_payments(input)
      scope = Payment.where(mode: "live").where.not(risk_decision: nil)
      scope = scope.where(risk_decision: input["decision"]) if input["decision"].present?
      count = scope.count
      limit = (input["limit"] || 10).to_i.clamp(1, 25)

      recent = scope.order(created_at: :desc).limit(limit).map do |p|
        {
          id:            p.public_id,
          risk_decision: p.risk_decision,
          risk_score:    p.risk_score&.round(4),
          amount:        format_amount(p.amount.to_i, p.currency),
          currency:      p.currency,
          status:        p.status,
          created_at:    p.created_at&.strftime("%Y-%m-%d %H:%M UTC")
        }
      end

      { total_count: count, recent: recent }
    end

    def get_settlement_pipeline
      core = CoreApiClient.new
      result = core.get_ops_settlement_dashboard
      return { error: "settlement data unavailable" } unless result.success?

      body = result.body
      {
        pipeline:          body["pipeline"],
        failed_last_5:     body["failed_disbursements"]&.first(5)
      }
    end

    def get_merchant_payables
      core = CoreApiClient.new
      result = core.get_ops_settlement_dashboard
      return { error: "payables data unavailable" } unless result.success?

      payables = result.body["merchant_payables"] || []
      payables.first(10).map do |p|
        p.slice("merchant_code", "merchant_name", "payable_amount", "currency")
      end
    end

    def get_provider_breakdown(input)
      period = input["period"] || "mtd"
      range  = PERIOD_RANGES.fetch(period, PERIOD_RANGES["mtd"]).call
      scope  = live_payments.where(status: %w[paid refunded], paid_at: range)

      # Group by (provider/method, currency) so amounts are currency-correct
      provider_totals = scope.group(:provider, :currency).sum(:amount)
      method_totals   = scope.group(:payment_method, :currency).sum(:amount)
      grand_total     = scope.sum(:amount).to_f

      provider_data = provider_totals.sort_by { |_, amt| -amt }.map do |(provider, currency), amt|
        pct = grand_total.positive? ? (amt.to_f / grand_total * 100).round(1) : 0.0
        {
          provider: provider,
          name:     Payment::PROVIDERS.fetch(provider.to_s, provider.to_s.humanize),
          amount:   format_amount(amt.to_i, currency),
          share:    "#{pct}%"
        }
      end

      method_data = method_totals.map do |(method, currency), amt|
        pct = grand_total.positive? ? (amt.to_f / grand_total * 100).round(1) : 0.0
        {
          method: method,
          amount: format_amount(amt.to_i, currency),
          share:  "#{pct}%"
        }
      end

      { period: period, provider_data: provider_data, method_data: method_data }
    end

    def get_dispute_summary(input)
      scope = Dispute.all
      scope = scope.where(status: input["status"]) if input["status"].present?
      scope.group(:status).count
    end

    def get_reconciliation_health
      today = Date.current
      breaks = Payment.where(mode: "live")
                      .where(created_at: today.beginning_of_day..today.end_of_day)
      {
        date:         today.iso8601,
        total_today:  breaks.count,
        # Recon breaks tracked in Core — fetch via API
        note: "Full recon health available via Core reconciliation-breaks endpoint."
      }
    end

    def get_merchant_stats(input)
      code   = input["merchant_code"].to_s.strip
      return { error: "merchant_code is required" } if code.blank?

      application = PortalMerchantApplication.find_by(merchant_code: code)
      merchant    = PortalMerchant.find_for(code)

      period = input["period"] || "mtd"
      range  = PERIOD_RANGES.fetch(period, PERIOD_RANGES["mtd"]).call
      scope  = Payment.for_merchant(code)

      paid    = scope.where(status: %w[paid refunded], paid_at: range)
      all_in  = scope.where(created_at: range)
      count   = all_in.count
      success = paid.count

      volume_by_currency = paid.group(:currency).sum(:amount)
                               .map { |cur, amt| "#{cur}: #{format_amount(amt.to_i, cur)}" }

      by_method = scope.where(created_at: range)
                       .group(:payment_method)
                       .select(:payment_method, "COUNT(*) AS cnt")
                       .map { |r| [ r.payment_method, r.cnt.to_i ] }.to_h

      {
        merchant_code:      code,
        legal_name:         application&.legal_name,
        trading_name:       application&.trading_name,
        kyb_status:         application&.status,
        live_enabled:       merchant&.live_mode_enabled,
        period:             period,
        volume_by_currency: volume_by_currency,
        tx_count:           count,
        success_count:      success,
        success_rate:       count.positive? ? "#{(success.to_f / count * 100).round(1)}%" : "n/a",
        by_method:          by_method
      }
    end

    def get_kyb_queue
      stats = Compliance::KybReviewStatsQuery.new.call

      recent = PortalMerchantApplication.pending_review
                                        .order(last_applied_at: :desc)
                                        .limit(5)
                                        .map do |a|
        {
          application_code: a.application_code,
          legal_name:       a.legal_name,
          trading_name:     a.trading_name.presence,
          status:           a.status,
          submitted_at:     a.last_applied_at&.strftime("%Y-%m-%d")
        }
      end

      {
        pending_total:   stats[:pending] + stats[:in_review],
        awaiting_review: stats[:pending],
        in_review:       stats[:in_review],
        approved_30d:    stats[:approved_30d],
        rejected_30d:    stats[:rejected_30d],
        recent_pending:  recent
      }
    end

    def format_amount(minor_units, currency = "GHS")
      cur = currency.to_s.upcase.presence || "GHS"
      return "#{cur} 0.00" if minor_units.nil? || minor_units.zero?
      "#{cur} #{format('%.2f', minor_units.to_f / 100)}"
    end
  end
end
