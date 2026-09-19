# frozen_string_literal: true

module Checkout
  class InvoicesController < ApplicationController
    def index
      authorize :invoice, :index?
      tab    = params[:tab].presence_in(%w[all draft open overdue paid void]) || "all"
      state  = tab == "all" ? nil : tab
      result = core.list_invoices(merchant_code: current_user.merchant_code, state: state)
      invoices = result.success? ? (result.body["data"] || []) : []
      invoices = filter_invoices(invoices)
      render Checkout::Invoices::IndexView.new(
        invoices: invoices,
        query:    params[:q],
        tab:      tab
      )
    end

    def show
      authorize :invoice, :show?
      result = core.get_invoice(params[:id])
      return redirect_to invoices_path, alert: "Invoice not found." unless result.success?
      render Checkout::Invoices::ShowView.new(invoice: result.body)
    end

    def new
      authorize :invoice, :create?
      render Checkout::Invoices::FormView.new
    end

    def create
      authorize :invoice, :create?

      line_items = parse_line_items(params[:line_items] || [])
      if line_items.empty?
        return render Checkout::Invoices::FormView.new(errors: ["Add at least one line item."]),
                      status: :unprocessable_entity
      end

      result = core.create_invoice(
        merchant_code:      current_user.merchant_code,
        customer_reference: params[:customer_reference],
        number:             params[:number],
        currency:           params[:currency].presence || "GHS",
        issue_date:         params[:issue_date],
        due_date:           params[:due_date],
        notes:              params[:notes].presence,
        terms:              params[:terms].presence,
        line_items:         line_items
      )

      if result.success?
        redirect_to invoice_path(result.body["id"]), notice: "Invoice created."
      else
        render Checkout::Invoices::FormView.new(errors: [ result.error_message ]),
               status: :unprocessable_entity
      end
    end

    def issue
      authorize :invoice, :update?

      allowed_methods = Array(params[:allowed_methods]).select do |m|
        %w[mobile_money card bank_transfer].include?(m)
      end
      allowed_methods = ["mobile_money"] if allowed_methods.empty?

      payment_config = {
        allowed_methods: allowed_methods,
        collect_email:   params[:collect_email] == "true",
        collect_phone:   params[:collect_phone] == "true",
        collect_name:    params[:collect_name]  == "true"
      }

      result = core.issue_invoice(params[:id], payment_config)
      if result.success?
        redirect_to invoice_path(params[:id]), notice: "Invoice issued — payment link is ready to share."
      else
        redirect_to invoice_path(params[:id]), alert: result.error_message
      end
    end

    def void
      authorize :invoice, :update?
      result = core.void_invoice(params[:id])
      if result.success?
        redirect_to invoice_path(params[:id]), notice: "Invoice voided."
      else
        redirect_to invoice_path(params[:id]), alert: result.error_message
      end
    end

    private

    def filter_invoices(invoices)
      return invoices if params[:q].blank?
      q = params[:q].downcase
      invoices.select do |inv|
        inv["number"].to_s.downcase.include?(q) ||
          inv["customer_reference"].to_s.downcase.include?(q)
      end
    end

    def parse_line_items(raw)
      Array(raw).filter_map do |item|
        next if item[:description].blank? && item["description"].blank?
        {
          description:  item[:description]  || item["description"],
          quantity:     (item[:quantity]     || item["quantity"] || 1).to_f,
          unit_amount:  ((item[:unit_amount] || item["unit_amount"]).to_f * 100).round,
          tax_rate_bps: (item[:tax_rate_bps] || item["tax_rate_bps"] || 0).to_i
        }
      end
    end

    def core
      @core ||= CoreApiClient.new
    end
  end
end
