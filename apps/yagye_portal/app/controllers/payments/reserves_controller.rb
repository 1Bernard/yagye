# frozen_string_literal: true

module Payments
  class ReservesController < ApplicationController
    XLSX_TYPE = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"

    EXPORT_COLUMNS = {
      "Payment ID"   => ->(h) { h["payment_public_id"].presence || h["payment_id"].to_s },
      "Reference"    => ->(h) { h["payment_reference"].to_s },
      "Amount (GHS)" => ->(h) { "%.2f" % (h["amount"].to_i / 100.0) },
      "Status"       => ->(h) { h["state"].to_s },
      "Held on"      => ->(h) { h["held_at"].to_s },
      "Release date" => ->(h) { h["release_at"].to_s },
      "Released on"  => ->(h) { h["released_at"].to_s },
      "Drawn on"     => ->(h) { h["drawn_at"].to_s }
    }.freeze

    def index
      authorize :reserve, :index?, policy_class: ReservePolicy
      client       = CoreApiClient.new
      mc           = current_user.merchant_code
      state_filter = params[:state].presence_in(%w[pending released drawn])
      q            = params[:q].presence
      from         = params[:from].presence
      to           = params[:to].presence
      page         = params[:page].to_i.clamp(1, 9999)

      result     = client.get_reserves(mc, limit: 25, offset: (page - 1) * 25,
                                           state: state_filter, q: q, from: from, to: to)
      forecast_r = client.get_reserve_forecast(mc)

      data     = result.success? ? result.body : {}
      forecast = forecast_r.success? ? forecast_r.body : {}

      render Payments::Reserves::IndexView.new(
        policy:       data["policy"],
        summary:      data["summary"] || {},
        holds:        data["holds"]   || [],
        forecast:     forecast,
        state_filter: state_filter,
        q:            q,
        from:         from,
        to:           to,
        page:         page,
        total:        data.dig("meta", "total").to_i
      )
    end

    def filter
      authorize :reserve, :index?, policy_class: ReservePolicy
      render Payments::Reserves::FilterView.new(
        q:    params[:q],
        from: params[:from],
        to:   params[:to]
      )
    end

    def export
      authorize :reserve, :index?, policy_class: ReservePolicy
      q    = params[:q].presence
      from = params[:from].presence
      to   = params[:to].presence
      result = CoreApiClient.new.export_reserve_holds(current_user.merchant_code, q: q, from: from, to: to)
      holds  = result.success? ? (result.body["holds"] || []) : []

      respond_to do |format|
        format.csv  { stream_reserve_csv(holds) }
        format.xlsx { send_reserve_xlsx(holds) }
      end
    end

    private

    def stream_reserve_csv(holds)
      filename = "reserve-holds-#{Date.current.iso8601}.csv"
      headers["Content-Type"]        = "text/csv; charset=utf-8"
      headers["Content-Disposition"] = "attachment; filename=\"#{filename}\""
      csv_data = CSV.generate(headers: true) do |csv|
        csv << EXPORT_COLUMNS.keys
        holds.each { |h| csv << EXPORT_COLUMNS.values.map { |fn| fn.call(h) } }
      end
      render plain: csv_data
    end

    def send_reserve_xlsx(holds)
      data = Exports::ExcelExport.new(
        records:    holds,
        columns:    EXPORT_COLUMNS,
        sheet_name: "Reserve Holds"
      ).call
      send_data data,
                type:        XLSX_TYPE,
                filename:    "reserve-holds-#{Date.current.iso8601}.xlsx",
                disposition: "attachment"
    end

    public

    def acknowledge
      authorize :reserve, :acknowledge?, policy_class: ReservePolicy

      result = CoreApiClient.new.acknowledge_reserve_policy(
        params[:id],
        acknowledged_by: current_user.user_code
      )

      if result.success?
        AuditLog.record(
          actor:         current_user,
          action:        "reserve_policy.acknowledged",
          resource_type: "merchant",
          resource_code: current_user.merchant_code,
          outcome:       "succeeded"
        )
        redirect_to reserves_path,
                    notice: "Reserve policy acknowledged. Funds will be withheld from your next settlement."
      else
        redirect_to reserves_path, alert: result.error_message
      end
    end
  end
end
