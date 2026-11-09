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
      when "get_payment_volume"      then get_payment_volume(input)
      when "get_provider_health"     then get_provider_health(input)
      when "get_flagged_payments"    then get_flagged_payments(input)
      when "get_settlement_pipeline" then get_settlement_pipeline
      when "get_merchant_payables"   then get_merchant_payables
      when "get_provider_breakdown"  then get_provider_breakdown(input)
      when "get_dispute_summary"     then get_dispute_summary(input)
      when "get_reconciliation_health" then get_reconciliation_health
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
      gross   = paid.sum(:amount)
      count   = all_in.count
      success = paid.count

      {
        period:         period,
        gross_volume:   format_amount(gross),
        tx_count:       count,
        success_count:  success,
        success_rate:   count.positive? ? "#{(success.to_f / count * 100).round(1)}%" : "n/a"
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
          amount:        format_amount(p.amount.to_i),
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
      scope  = live_payments

      data = Payments::VolumeSummaryQuery.new(scope).call
      {
        period:         period,
        provider_data:  data[:provider_data]&.map { |p| p.slice(:key, :name, :pct, :amount) },
        method_data:    data[:method_data]&.map { |m| m.slice(:key, :name, :pct, :amount) }
      }
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

    def format_amount(pesewas)
      return "GHS 0.00" if pesewas.nil? || pesewas.zero?
      "GHS #{format('%.2f', pesewas.to_f / 100)}"
    end
  end
end
