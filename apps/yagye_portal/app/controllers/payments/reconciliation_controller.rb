# frozen_string_literal: true

module Payments
  class ReconciliationController < ApplicationController
    def index
      authorize :reconciliation, :index?
      api_params = { provider_code: params[:provider], state: params[:state],
                     severity: params[:severity] }.stringify_keys
      result = CoreApiClient.new.list_all_reconciliation_breaks(api_params)
      breaks = result.success? ? (result.body["data"] || []) : []
      breaks = filter_breaks(breaks)

      respond_to do |format|
        format.html do
          render Payments::Reconciliation::IndexView.new(
            breaks:          breaks,
            query:           params[:q],
            provider_filter: params[:provider],
            state_filter:    params[:state],
            severity_filter: params[:severity],
            from:            params[:from],
            to:              params[:to]
          )
        end
        format.csv do
          send_data build_breaks_csv(breaks),
                    filename: "reconciliation_breaks_#{Date.current.iso8601}.csv",
                    type:     "text/csv",
                    disposition: "attachment"
        end
      end
    end

    def filter
      authorize :reconciliation, :index?
      render Payments::Reconciliation::FilterView.new(
        query:    params[:q],
        state:    params[:state],
        severity: params[:severity],
        from:     params[:from],
        to:       params[:to]
      )
    end

    def show
      authorize :reconciliation, :show?
      result = CoreApiClient.new.get_reconciliation_break(params[:id])
      if result.success?
        render Payments::Reconciliation::ShowView.new(recon_break: result.body)
      else
        redirect_to reconciliation_path, alert: "Reconciliation break not found."
      end
    end

    def propose_adjustment_modal
      authorize :reconciliation, :propose_adjustment?
      result = CoreApiClient.new.get_reconciliation_break(params[:id])
      if result.success?
        render Payments::Reconciliation::ProposeAdjustmentModalView.new(recon_break: result.body)
      else
        head :not_found
      end
    end

    def propose_adjustment
      authorize :reconciliation, :propose_adjustment?
      result = CoreApiClient.new.propose_reconciliation_adjustment(
        params[:id],
        proposed_by:     current_user.user_code,
        amount:          params[:amount].to_i,
        direction:       params[:direction],
        resolution_code: params[:resolution_code],
        resolution_note: params[:resolution_note].presence
      )
      if result.success?
        redirect_to reconciliation_break_path(params[:id]),
                    notice: "Adjustment proposed and pending approval."
      else
        redirect_to reconciliation_break_path(params[:id]),
                    alert: "Failed to propose adjustment: #{result.error_message}"
      end
    end

    def upload_report_modal
      authorize :reconciliation, :upload_report?
      render Payments::Reconciliation::UploadReportModalView.new
    end

    def upload_report
      authorize :reconciliation, :upload_report?

      uploaded_file = params[:csv_file]
      provider_code = params[:provider_code].to_s.strip
      mode          = params[:mode].presence_in(%w[live simulation sandbox]) || "live"
      currency      = params[:currency].presence_in(%w[GHS USD EUR GBP]) || "GHS"

      if provider_code.blank?
        return redirect_to reconciliation_path, alert: "Please select a provider."
      end

      unless uploaded_file.respond_to?(:read)
        return redirect_to reconciliation_path, alert: "Please select a CSV file to upload."
      end

      csv_content = uploaded_file.read.force_encoding("UTF-8").encode("UTF-8",
                      invalid: :replace, undef: :replace, replace: "")

      result = CoreApiClient.new.upload_settlement_report(
        provider_code: provider_code,
        mode:          mode,
        currency:      currency,
        csv_content:   csv_content
      )

      if result.success?
        line_count = result.body["line_count"]
        runs       = result.body["runs_triggered"]
        redirect_to reconciliation_path,
                    notice: "Report uploaded — #{line_count} lines ingested, " \
                            "#{runs} reconciliation run(s) triggered."
      elsif result.error_code == "duplicate_report"
        redirect_to reconciliation_path,
                    alert: "This report has already been imported (duplicate checksum)."
      else
        msg = result.body.dig("error", "message").presence || "Upload failed."
        redirect_to reconciliation_path, alert: msg
      end
    end

    private

    def filter_breaks(breaks)
      if params[:q].present?
        q = params[:q].downcase
        breaks = breaks.select do |b|
          b["id"].to_s.downcase.include?(q) ||
            b["classification"].to_s.downcase.include?(q) ||
            b["provider_code"].to_s.downcase.include?(q) ||
            b["merchant_name"].to_s.downcase.include?(q) ||
            b["merchant_code"].to_s.downcase.include?(q) ||
            b["left_ref"].to_s.downcase.include?(q) ||
            b["right_ref"].to_s.downcase.include?(q)
        end
      end
      breaks = breaks.select { |b| b["state"]    == params[:state]    } if params[:state].present?
      breaks = breaks.select { |b| b["severity"] == params[:severity] } if params[:severity].present?
      if params[:from].present?
        from = begin; Date.parse(params[:from]); rescue ArgumentError; nil; end
        breaks = breaks.select { |b| b["detected_at"] && Date.parse(b["detected_at"]) >= from } if from
      end
      if params[:to].present?
        to = begin; Date.parse(params[:to]); rescue ArgumentError; nil; end
        breaks = breaks.select { |b| b["detected_at"] && Date.parse(b["detected_at"]) <= to } if to
      end
      breaks
    end

    def build_breaks_csv(breaks)
      require "csv"
      headers = %w[id provider_code merchant_name merchant_code classification severity state
                   left_ref right_ref expected_amount actual_amount difference currency
                   detected_at sla_due_at assigned_to resolution_code]
      CSV.generate(headers: true) do |csv|
        csv << headers
        breaks.each { |b| csv << headers.map { |h| b[h] } }
      end
    end
  end
end
