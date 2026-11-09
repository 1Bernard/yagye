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
          description: "Returns this merchant's current payout balance: available, pending, and in-transit amounts.",
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

      paid   = scope.where(status: %w[paid refunded], paid_at: range)
      all_in = scope.where(created_at: range)
      gross  = paid.sum(:amount)
      count  = all_in.count
      success = paid.count

      {
        period:        period,
        gross_volume:  format_amount(gross),
        tx_count:      count,
        success_count: success,
        success_rate:  count.positive? ? "#{(success.to_f / count * 100).round(1)}%" : "n/a"
      }
    end

    def get_my_recent_payments(input)
      limit = (input["limit"] || 10).to_i.clamp(1, 25)
      scope = scoped_payments
      scope = scope.where(status: input["status"]) if input["status"].present?

      scope.order(created_at: :desc).limit(limit).map do |p|
        {
          id:         p.public_id,
          amount:     format_amount(p.amount.to_i),
          status:     p.status,
          method:     p.payment_method,
          created_at: p.created_at&.strftime("%Y-%m-%d %H:%M UTC")
        }
      end
    end

    def get_my_payout_balance
      result = Payouts::BalanceSummaryQuery.new(scoped_payments).call
      {
        available:  format_amount(result[:available].to_i),
        pending:    format_amount(result[:pending].to_i),
        in_transit: format_amount(result[:in_transit].to_i)
      }
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

    def format_amount(pesewas)
      return "GHS 0.00" if pesewas.nil? || pesewas.zero?
      "GHS #{format('%.2f', pesewas.to_f / 100)}"
    end
  end
end
