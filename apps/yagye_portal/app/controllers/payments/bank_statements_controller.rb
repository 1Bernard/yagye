# frozen_string_literal: true

module Payments
  class BankStatementsController < ApplicationController
    def index
      authorize :bank_statements, :index?
      account_ref = params[:account_reference].presence
      result = CoreApiClient.new.list_bank_statements(account_reference: account_ref)
      statements = result.success? ? (result.body["data"] || []) : []
      render Payments::BankStatements::IndexView.new(statements: statements, account_reference: account_ref)
    end

    def show
      authorize :bank_statements, :show?
      result = CoreApiClient.new.get_bank_statement(params[:id])
      unless result.success?
        return redirect_to payments_bank_statements_path, alert: "Bank statement not found."
      end
      render Payments::BankStatements::ShowView.new(statement: result.body)
    end

    def new
      authorize :bank_statements, :new?
      render Payments::BankStatements::NewView.new
    end

    def create
      authorize :bank_statements, :create?

      account_reference = params[:account_reference].to_s.strip
      statement_date    = params[:statement_date].to_s.strip
      raw_csv           = params[:csv_lines].to_s.strip
      currency          = params[:currency].presence_in(%w[GHS USD EUR GBP]) || "GHS"
      mode              = params[:mode].presence_in(%w[live simulation]) || "live"
      opening_balance   = (params[:opening_balance].to_f * 100).round
      closing_balance   = (params[:closing_balance].to_f * 100).round

      if account_reference.blank? || statement_date.blank? || raw_csv.blank?
        return redirect_to new_payments_bank_statement_path,
                           alert: "Account reference, date, and CSV lines are required."
      end

      lines = parse_csv_lines(raw_csv, currency: currency)
      if lines.empty?
        return redirect_to new_payments_bank_statement_path, alert: "No valid CSV lines found."
      end

      checksum = Digest::SHA256.hexdigest(raw_csv)[0, 32]
      raw_uri  = "portal://csv_upload/#{checksum}"

      result = CoreApiClient.new.create_bank_statement(
        account_reference: account_reference,
        statement_date:    statement_date,
        currency:          currency,
        mode:              mode,
        source:            "csv_upload",
        opening_balance:   opening_balance,
        closing_balance:   closing_balance,
        checksum:          checksum,
        raw_uri:           raw_uri,
        lines:             lines
      )

      if result.success?
        id = result.body["id"]
        redirect_to payments_bank_statement_path(id), notice: "Statement imported — #{lines.size} lines."
      elsif result.error_code == "duplicate_statement"
        redirect_to payments_bank_statements_path,
                    alert: "Duplicate statement: this file has already been imported."
      else
        msg = result.body.dig("error", "message").presence ||
              result.body.dig("error", "errors").to_s.presence ||
              "Import failed."
        redirect_to new_payments_bank_statement_path, alert: msg
      end
    end

    private

    def parse_csv_lines(raw, currency: "GHS")
      raw.lines.each_with_index.filter_map do |line, idx|
        parts = line.strip.split(",")
        next if parts.size < 3
        value_date = parts[0].strip
        narrative  = parts[1].to_s.strip
        amount_str = parts[2].strip
        next if value_date.blank? || amount_str.blank?
        amount = (amount_str.to_f * 100).round
        {
          line_number: idx + 1,
          value_date:  value_date,
          narrative:   narrative,
          amount:      amount,
          currency:    currency
        }
      end
    end
  end
end
