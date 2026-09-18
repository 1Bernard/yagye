# frozen_string_literal: true

module Payments
  class ReconciliationController < ApplicationController
    def index
      authorize :reconciliation, :index?
      result = CoreApiClient.new.list_all_reconciliation_breaks
      breaks = result.success? ? (result.body["data"] || []) : []
      breaks = filter_breaks(breaks)
      render Payments::Reconciliation::IndexView.new(
        breaks:          breaks,
        query:           params[:q],
        state_filter:    params[:state],
        severity_filter: params[:severity],
        from:            params[:from],
        to:              params[:to]
      )
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

    private

    def filter_breaks(breaks)
      if params[:q].present?
        q = params[:q].downcase
        breaks = breaks.select do |b|
          b["id"].to_s.downcase.include?(q) ||
            b["classification"].to_s.downcase.include?(q)
        end
      end
      breaks = breaks.select { |b| b["state"]    == params[:state]    } if params[:state].present?
      breaks = breaks.select { |b| b["severity"] == params[:severity] } if params[:severity].present?
      if params[:from].present?
        from = Date.parse(params[:from]) rescue nil
        breaks = breaks.select { |b| b["detected_at"] && Date.parse(b["detected_at"]) >= from } if from
      end
      if params[:to].present?
        to = Date.parse(params[:to]) rescue nil
        breaks = breaks.select { |b| b["detected_at"] && Date.parse(b["detected_at"]) <= to } if to
      end
      breaks
    end
  end
end
