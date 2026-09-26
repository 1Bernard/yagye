# frozen_string_literal: true

module Payments
  class TransactionsController < ApplicationController
    XLSX_TYPE = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"

    def index
      authorize Payment, :index?
      base_scope    = policy_scope(Payment)
      @is_ops       = current_user.internal_staff?
      @can_export   = policy(Payment).export?
      @can_view_pii = policy(Payment).view_customer_pii?

      query_scope = @is_ops ? Payments::TransactionsQuery.with_merchant_name(base_scope) : base_scope

      @filtered = Payments::TransactionsQuery.new(query_scope).call(filters)

      respond_to do |format|
        format.html do
          pagy, payments = pagy(@filtered, limit: 25)
          render Payments::IndexView.new(
            payments:           payments,
            pagy:               pagy,
            stats:              payment_stats(base_scope),
            show_merchant:      @is_ops,
            can_view_pii:       @can_view_pii,
            can_export:         @can_export,
            status_filter:      params[:status],
            method_filter:      params[:method],
            from:               params[:from],
            to:                 params[:to],
            query:              params[:q],
            payments_stream_key: payments_stream_key
          )
        end
        format.csv do
          return redirect_to payments_path, alert: "Export not permitted." unless @can_export
          stream_csv_export(@filtered)
        end
        format.xlsx do
          return redirect_to payments_path, alert: "Export not permitted." unless @can_export
          return redirect_to payments_path, alert: "Too many rows for Excel export — use CSV for large datasets." if @filtered.count > 2_000
          send_export_data(Exports::ExcelExport, @filtered.limit(2_000), XLSX_TYPE, "xlsx")
        end
        format.pdf do
          return redirect_to payments_path, alert: "Export not permitted." unless @can_export
          return redirect_to payments_path, alert: "Too many rows for PDF export — use CSV for large datasets." if @filtered.count > 2_000
          send_export_data(Exports::PdfExport, @filtered.limit(2_000), "application/pdf", "pdf")
        end
      end
    end

    def filter
      authorize Payment, :index?
      render Payments::FilterView.new(
        query:   params[:q],
        status:  params[:status],
        method:  params[:method],
        from:    params[:from],
        to:      params[:to]
      )
    end

    def show
      payment = decode_id(Payment)
      authorize payment

      events = []
      if payment.core_payment_id.present?
        result = CoreApiClient.new.get_payment_events(payment.core_payment_id)
        events = result.body["data"] || [] if result.success?
      end

      render Payments::ShowView.new(
        payment:         payment,
        events:          events,
        can_refund:      policy(payment).refund?,
        can_view_pii:    policy(payment).view_customer_pii?,
        other_payments:  customer_other_payments(payment)
      )
    end

    def refund
      payment = decode_id(Payment)
      authorize payment, :refund?
      amount = params[:amount].present? ? params[:amount].to_i : payment.amount
      result = CoreApiClient.new.create_refund(
        payment.core_payment_id,
        amount:       amount,
        reason:       params[:reason].to_s.strip.presence || "requested_by_merchant",
        initiated_by: current_user.user_code
      )
      if result.success?
        redirect_to payment_path(payment), notice: "Refund initiated."
      else
        redirect_to payment_path(payment), alert: result.error_message
      end
    end

    private

    def stream_csv_export(scope)
      filename = "payments-#{Date.current.iso8601}.csv"
      headers["Content-Type"]        = "text/csv; charset=utf-8"
      headers["Content-Disposition"] = "attachment; filename=\"#{filename}\""
      headers["X-Accel-Buffering"]   = "no"  # prevent Nginx from buffering the whole response

      exporter = Exports::CsvExport.new(records: scope, columns: export_columns)
      self.response_body = Enumerator.new { |y| exporter.stream { |line| y << line } }
    end

    def send_export_data(exporter_class, records, content_type, extension)
      opts = { records: records, columns: export_columns }
      opts[:title] = "Payments" if exporter_class.instance_method(:initialize).parameters.any? { |_, n| n == :title }
      data = exporter_class.new(**opts).call
      send_data data,
                type:        content_type,
                filename:    "payments-#{Date.current.iso8601}.#{extension}",
                disposition: "attachment"
    end

    def export_columns
      cols = {}
      cols["Merchant"]        = ->(p) { p.try(:merchant_name) || p.merchant_code } if @is_ops
      cols["Reference"]       = :reference
      cols["Date"]            = ->(p) { p.created_at.strftime("%Y-%m-%d %H:%M") }
      cols["Amount (GHS)"]    = ->(p) { "%.2f" % (p.amount / 100.0) }
      cols["Fee (GHS)"]       = ->(p) { p.fee_amount ? ("%.2f" % (p.fee_amount / 100.0)) : "" }
      cols["Net (GHS)"]       = ->(p) { p.net_amount ? ("%.2f" % (p.net_amount / 100.0)) : "" }
      cols["Currency"]        = :currency
      cols["Status"]          = :status
      cols["Provider"]        = :provider
      cols["Payment Method"]  = :payment_method
      if @can_view_pii
        cols["Customer MSISDN"] = :customer_msisdn
        cols["Customer Email"]  = :customer_email
      end
      cols["Mode"]            = :mode
      cols["Payment ID"]      = :core_payment_id
      cols
    end

    def filters
      params.permit(:status, :q, :from, :to, :provider, :method).to_h.symbolize_keys
    end

    def customer_other_payments(payment)
      return [] if payment.customer_msisdn.blank?
      scope = current_user.internal_staff? ? Payment.all : Payment.for_merchant(current_user.merchant_code)
      scope.where(customer_msisdn: payment.customer_msisdn)
           .where.not(id: payment.id)
           .order(created_at: :desc)
           .limit(5)
    rescue StandardError
      []
    end

    def payments_stream_key
      return nil if current_user.internal_staff?
      mode = Current.mode.presence || "live"
      "payments_#{current_user.merchant_code}_#{mode}"
    end

    def payment_stats(scope)
      mtd_start = Time.current.beginning_of_month
      paid_mtd  = scope.where(status: "paid").where("paid_at >= ?", mtd_start)
      {
        volume_mtd:       paid_mtd.sum(:amount),
        volume_currency:  scope.pick(:currency) || "GHS",
        transactions_mtd: paid_mtd.count,
        pending:          scope.where(status: %w[created processing requires_action]).count,
        failed:           scope.where(status: %w[failed cancelled]).count
      }
    end
  end
end
