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
      render Checkout::Invoices::ShowView.new(invoice: result.body, logo_url: extract_logo_url(result.body))
    end

    def new
      authorize :invoice, :create?
      render Checkout::Invoices::FormView.new(mode: Current.mode, logo_url: merchant_logo_url)
    end

    def create
      authorize :invoice, :create?

      line_items = parse_line_items(params[:line_items] || [])
      if line_items.empty?
        return render Checkout::Invoices::FormView.new(errors: [ "Add at least one line item." ], mode: Current.mode, logo_url: merchant_logo_url),
                      status: :unprocessable_entity
      end

      result = core.create_invoice(
        merchant_code:      current_user.merchant_code,
        customer_reference: params[:customer_reference],
        number:             params[:number],
        currency:           params[:currency].presence || "GHS",
        issue_date:         params[:issue_date],
        due_date:           params[:due_date],
        discount_amount:    parse_amount(params[:discount_amount]),
        notes:              params[:notes].presence,
        terms:              params[:terms].presence,
        pdf_s3_key:         params[:pdf_s3_key].presence,
        line_items:         line_items
      )

      if result.success?
        invoice_id = result.body["id"]
        if params[:save_as_draft] == "1"
          redirect_to invoice_path(invoice_id), notice: "Draft saved."
        else
          core.issue_invoice(invoice_id, payment_config_from_params)
          redirect_to invoice_path(invoice_id), notice: "Invoice issued — share the link with your customer."
        end
      else
        render Checkout::Invoices::FormView.new(errors: extract_errors(result), mode: Current.mode, logo_url: merchant_logo_url),
               status: :unprocessable_entity
      end
    end

    def edit
      authorize :invoice, :update?
      result = core.get_invoice(params[:id])
      return redirect_to invoices_path, alert: "Invoice not found." unless result.success?
      invoice = result.body
      unless invoice["state"] == "draft"
        return redirect_to invoice_path(params[:id]), alert: "Only draft invoices can be edited."
      end
      render Checkout::Invoices::FormView.new(invoice: invoice, mode: Current.mode, logo_url: extract_logo_url(invoice))
    end

    def update
      authorize :invoice, :update?

      line_items = parse_line_items(params[:line_items] || [])
      if line_items.empty?
        re = core.get_invoice(params[:id])
        return render Checkout::Invoices::FormView.new(
          invoice:  re.success? ? re.body : nil,
          errors:   [ "Add at least one line item." ],
          mode:     Current.mode,
          logo_url: extract_logo_url(re.success? ? re.body : nil)
        ), status: :unprocessable_entity
      end

      result = core.update_invoice(
        params[:id],
        customer_reference: params[:customer_reference],
        number:             params[:number],
        currency:           params[:currency].presence || "GHS",
        issue_date:         params[:issue_date],
        due_date:           params[:due_date],
        discount_amount:    parse_amount(params[:discount_amount]),
        notes:              params[:notes].presence,
        terms:              params[:terms].presence,
        pdf_s3_key:         params[:pdf_s3_key].presence,
        line_items:         line_items
      )

      if result.success?
        if params[:save_as_draft] == "1"
          redirect_to invoice_path(params[:id]), notice: "Draft saved."
        else
          core.issue_invoice(params[:id], payment_config_from_params)
          redirect_to invoice_path(params[:id]), notice: "Invoice issued — share the link with your customer."
        end
      else
        re = core.get_invoice(params[:id])
        render Checkout::Invoices::FormView.new(
          invoice:  re.success? ? re.body : nil,
          errors:   extract_errors(result),
          mode:     Current.mode,
          logo_url: extract_logo_url(re.success? ? re.body : nil)
        ), status: :unprocessable_entity
      end
    end

    def issue
      authorize :invoice, :update?
      result = core.issue_invoice(params[:id], payment_config_from_params)
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

    def duplicate
      authorize :invoice, :create?
      result = core.get_invoice(params[:id])
      return redirect_to invoices_path, alert: "Invoice not found." unless result.success?
      render Checkout::Invoices::FormView.new(prefill: result.body, mode: Current.mode, logo_url: extract_logo_url(result.body))
    end

    def extract_pdf
      authorize :invoice, :create?
      pdf_file = params[:pdf]
      return render json: { error: "No PDF provided." }, status: :bad_request unless pdf_file.present?

      upload = upload_pdf_to_s3(pdf_file)
      return render json: { error: upload[:error] }, status: :unprocessable_entity if upload[:error]

      pdf_text   = extract_pdf_text(pdf_file)
      extraction = Ai::InvoicePdfExtractor.new.extract(pdf_text)

      render json: {
        fields:           extraction.success? ? extraction.fields : {},
        pdf_s3_key:       upload[:s3_key],
        extraction_error: extraction.error
      }
    rescue StandardError => e
      Rails.logger.error("[InvoicesController#extract_pdf] #{e.class}: #{e.message}")
      render json: { error: "PDF processing failed — please enter details manually." }, status: :internal_server_error
    end

    private

    def payment_config_from_params
      allowed_methods = Array(params[:allowed_methods]).select do |m|
        %w[mobile_money card bank_transfer].include?(m)
      end
      allowed_methods = [ "mobile_money" ] if allowed_methods.empty?
      {
        allowed_methods: allowed_methods,
        collect_email:   params[:collect_email] == "true",
        collect_phone:   params[:collect_phone] == "true",
        collect_name:    params[:collect_name]  == "true"
      }
    end

    def extract_errors(result)
      if result.error_code == "validation_failed"
        details = result.body.dig("error", "details") || {}
        if details.any?
          details.flat_map { |field, msgs| msgs.map { |m| "#{field.to_s.humanize} #{m}" } }
        else
          [ result.error_message ]
        end
      else
        [ result.error_message ]
      end
    end

    def filter_invoices(invoices)
      return invoices if params[:q].blank?
      q = params[:q].downcase
      invoices.select do |inv|
        inv["number"].to_s.downcase.include?(q) ||
          inv["customer_reference"].to_s.downcase.include?(q)
      end
    end

    def parse_amount(raw)
      return nil if raw.blank?
      (raw.to_f * 100).round
    end

    def parse_line_items(raw)
      # Form sends line_items as a hash keyed by index ("0", "1", …).
      # Array() on a hash yields [key, value] pairs — useless. Normalize to values first.
      items = raw.respond_to?(:each_value) ? raw.values : Array(raw)
      items.filter_map do |item|
        next if item[:description].blank? && item["description"].blank?
        {
          description:  item[:description]  || item["description"],
          quantity:     (item[:quantity]     || item["quantity"] || 1).to_f,
          unit_amount:  ((item[:unit_amount] || item["unit_amount"]).to_f * 100).round,
          tax_rate_bps: (item[:tax_rate_bps] || item["tax_rate_bps"] || 0).to_i
        }
      end
    end

    def extract_logo_url(invoice)
      return nil unless invoice
      invoice.dig("checkout_layout", "logo_url").presence ||
        invoice.dig("payment_link", "checkout_layout", "logo_url").presence
    end

    def merchant_logo_url
      result = core.get_checkout_config(current_user.merchant_code)
      result.success? ? result.body["logo_url"].presence : nil
    end

    def extract_pdf_text(file)
      reader = PDF::Reader.new(file.path)
      reader.pages.map(&:text).join("\n").strip
    rescue PDF::Reader::MalformedPDFError, PDF::Reader::UnsupportedFeatureError
      ""
    end

    def upload_pdf_to_s3(file)
      result = core.presign_invoice_pdf(merchant_code: current_user.merchant_code)
      return { error: "Could not get upload URL — please try again." } unless result.success?

      presigned_url = rewrite_presigned_url(result.body["presigned_url"])
      s3_key        = result.body["s3_key"]

      uri  = URI.parse(presigned_url)
      req  = Net::HTTP::Put.new(uri)
      req["Content-Type"] = "application/pdf"
      req.body = File.binread(file.path)

      http           = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl   = uri.scheme == "https"
      http.read_timeout = 30
      response = http.request(req)

      if response.code.to_i < 300
        { s3_key: s3_key }
      else
        Rails.logger.warn("[InvoicesController#upload_pdf_to_s3] S3 PUT #{response.code}")
        { error: "PDF upload failed — please try again." }
      end
    end

    def core
      @core ||= CoreApiClient.new
    end
  end
end
