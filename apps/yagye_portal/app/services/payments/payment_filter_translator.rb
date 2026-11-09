# frozen_string_literal: true

module Payments
  # Translates an array of structured filter conditions into an ActiveRecord scope.
  # Zero SQL injection risk: field and operator are allowlisted; values are
  # always passed as bind parameters.
  #
  # Usage:
  #   scope = PaymentFilterTranslator.apply(Payment.all, params[:filters])
  #
  # Input shape (from query builder form):
  #   [
  #     { "field" => "payment_method", "op" => "eq",  "value" => "mobile_money" },
  #     { "field" => "amount",         "op" => "gte", "value" => "50000" },
  #     { "field" => "status",         "op" => "in",  "value" => "paid,failed" }
  #   ]
  class PaymentFilterTranslator
    ALLOWED_FIELDS = {
      "payment_method" => { column: "payment_method", type: :string },
      "status"         => { column: "status",         type: :string },
      "provider"       => { column: "provider",       type: :string },
      "network"        => { column: "network",        type: :string },
      "risk_decision"  => { column: "risk_decision",  type: :string },
      "amount"         => { column: "amount",         type: :integer },
      "created_at"     => { column: "created_at",     type: :datetime }
    }.freeze

    # Ops can filter by risk_decision; merchants cannot (not in merchant ALLOWED_FIELDS).
    MERCHANT_ALLOWED_FIELDS = ALLOWED_FIELDS.except("risk_decision").freeze

    STRING_OPS = {
      "eq"     => "= ?",
      "neq"    => "!= ?",
      "in"     => "IN (?)",
      "not_in" => "NOT IN (?)"
    }.freeze

    NUMERIC_OPS = {
      "eq"  => "= ?",
      "neq" => "!= ?",
      "gt"  => "> ?",
      "gte" => ">= ?",
      "lt"  => "< ?",
      "lte" => "<= ?"
    }.freeze

    DATE_OPS = NUMERIC_OPS

    def self.apply(scope, conditions, merchant: false)
      return scope if conditions.blank?

      allowed = merchant ? MERCHANT_ALLOWED_FIELDS : ALLOWED_FIELDS

      Array(conditions).each do |cond|
        field_key = cond["field"].to_s
        op        = cond["op"].to_s
        raw_value = cond["value"]

        meta = allowed[field_key]
        next unless meta   # skip unknown fields silently

        col, type = meta.values_at(:column, :type)

        case type
        when :string
          op_sql = STRING_OPS[op]
          next unless op_sql

          if op.in?(%w[in not_in])
            vals = Array(raw_value.to_s.split(",")).map(&:strip).reject(&:blank?)
            scope = scope.where("#{col} #{op_sql}", vals) if vals.any?
          else
            scope = scope.where("#{col} #{op_sql}", raw_value.to_s)
          end

        when :integer
          op_sql = NUMERIC_OPS[op]
          next unless op_sql && raw_value.to_s.match?(/\A-?\d+\z/)

          scope = scope.where("#{col} #{op_sql}", raw_value.to_i)

        when :datetime
          op_sql = DATE_OPS[op]
          next unless op_sql

          parsed = Time.zone.parse(raw_value.to_s) rescue nil
          scope  = scope.where("#{col} #{op_sql}", parsed) if parsed
        end
      end

      scope
    end
  end
end
