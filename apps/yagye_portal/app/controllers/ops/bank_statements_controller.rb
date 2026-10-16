# frozen_string_literal: true

module Ops
  class BankStatementsController < ApplicationController
    def index
      authorize :bank_statements, :index?
      account_ref = params[:account_reference].presence
      result = CoreApiClient.new.list_bank_statements(account_reference: account_ref)
      statements = result.success? ? (result.body["data"] || []) : []
      render Ops::BankStatements::IndexView.new(statements: statements, account_reference: account_ref)
    end

    def show
      authorize :bank_statements, :show?
      result = CoreApiClient.new.get_bank_statement(params[:id])
      unless result.success?
        return redirect_to ops_bank_statements_path, alert: "Bank statement not found."
      end
      render Ops::BankStatements::ShowView.new(statement: result.body)
    end

    def new
      authorize :bank_statements, :new?
      render Ops::BankStatements::NewView.new
    end

    def create
      authorize :bank_statements, :create?

      account_reference = params[:account_reference].to_s.strip
      statement_date    = params[:statement_date].to_s.strip
      raw_csv           = params[:csv_lines].to_s.strip

      if account_reference.blank? || statement_date.blank? || raw_csv.blank?
        return redirect_to new_ops_bank_statement_path,
                           alert: "Account reference, date, and CSV lines are required."
      end

      lines = parse_csv_lines(raw_csv)
      if lines.empty?
        return redirect_to new_ops_bank_statement_path, alert: "No valid CSV lines found."
      end

      result = CoreApiClient.new.import_bank_statement(
        account_reference: account_reference,
        statement_date:    statement_date,
        lines:             lines
      )

      if result.success?
        id = result.body["id"]
        redirect_to ops_bank_statement_path(id), notice: "Statement imported — #{lines.size} lines."
      elsif result.error_code == "duplicate_statement"
        redirect_to ops_bank_statements_path,
                    alert: "Duplicate statement: this file has already been imported."
      else
        redirect_to new_ops_bank_statement_path,
                    alert: "Import failed: #{result.error_message || "unknown error"}"
      end
    end

    private

    def parse_csv_lines(raw)
      raw.lines.filter_map do |line|
        parts = line.strip.split(",")
        next if parts.size < 4
        date, description, amount_str, checksum = parts[0], parts[1], parts[2], parts[3]
        next if date.blank? || amount_str.blank?
        amount = (amount_str.to_f * 100).round
        { date: date.strip, description: description.to_s.strip, amount: amount,
          checksum: checksum.to_s.strip }
      end
    end
  end
end
