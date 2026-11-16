# frozen_string_literal: true

module Checkout
  module Invoices
    class FormView < ApplicationComponent
      include UI::Theme

      CURRENCIES = [
        { code: "GHS", label: "GHS — Ghana Cedi",      symbol: "GH₵" },
        { code: "NGN", label: "NGN — Nigerian Naira",   symbol: "₦" },
        { code: "KES", label: "KES — Kenyan Shilling",  symbol: "KSh" },
        { code: "XOF", label: "XOF — West African CFA", symbol: "CFA" },
        { code: "USD", label: "USD — US Dollar",        symbol: "$" }
      ].freeze

      PAYMENT_METHODS = [
        { value: "mobile_money",  label: "Mobile Money",  desc: "MTN MoMo, Telecel Cash, AirtelTigo" },
        { value: "card",          label: "Card",           desc: "Visa and Mastercard" },
        { value: "bank_transfer", label: "Bank transfer",  desc: "Direct bank-to-bank transfers" }
      ].freeze

      DEMO = {
        customer:  "Kofi Builds Ltd.",
        number:    "INV-00042",
        currency:  "GHS",
        rows: [
          { description: "Web App Development",     qty: 1, unit: 3_500.00, tax: 0 },
          { description: "UX Design & Prototyping", qty: 1, unit: 1_200.00, tax: 0 }
        ],
        notes: "Thank you for choosing us — we appreciate your business.",
        terms: "Payment is due within 30 days of this invoice date."
      }.freeze

      def initialize(errors: [], mode: "test", invoice: nil, prefill: nil, logo_url: nil)
        @errors   = errors
        @mode     = mode
        @invoice  = invoice
        @prefill  = prefill
        @editing  = invoice.present?
        @logo_url = logo_url
      end

      def view_template
        crumbs = [ { label: "Invoices", href: invoices_path } ]
        crumbs << { label: @invoice["number"], href: invoice_path(@invoice["id"]) } if @editing
        crumbs << { label: @editing ? "Edit" : "New invoice" }

        render Layout::Shell.new(
          active_nav:   :invoices,
          title:        @editing ? "Edit #{@invoice["number"]}" : "New invoice",
          breadcrumbs:  crumbs,
          padded:       false,
          hide_sidebar: true,
          hide_topbar:  true
        ) do
          canvas_styles

          div(
            class: "relative h-full overflow-hidden",
            data: { controller: "invoice-compose" }
          ) do
            div(id: "invoice-canvas", class: "absolute inset-0")
            floating_toolbar
            form(
              id:     "invoice-form",
              action: @editing ? invoice_path(@invoice["id"]) : invoices_path,
              method: "post",
              class:  "absolute top-[76px] left-0 right-0 bottom-0"
            ) do
              input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
              input(type: "hidden", name: "_method", value: "patch") if @editing
              input(
                type:  "hidden",
                name:  "pdf_s3_key",
                value: @editing ? @invoice["pdf_s3_key"].to_s : "",
                data:  { invoice_compose_target: "pdfS3Key" }
              )
              editor_panel
              preview_area
            end
            back_btn_script
          end
        end
      end

      private

      # ── Canvas dot grid ──────────────────────────────────────────────────────

      def canvas_styles
        style do
          raw safe(%(
            #invoice-canvas {
              background-color: #f8fafc;
              background-image: radial-gradient(circle, #d1d5db 1px, transparent 1px);
              background-size: 24px 24px;
            }
            .composer-row input:focus { box-shadow: none; }
            .inv-preview { font-family: 'Inter', -apple-system, sans-serif; }
          ))
        end
      end

      # ── Floating toolbar ─────────────────────────────────────────────────────

      def floating_toolbar
        div(
          class: "absolute top-4 left-1/2 -translate-x-1/2 z-30 flex items-center gap-[6px] " \
                 "bg-white border border-gray-200/80 rounded-2xl px-[10px] py-[7px] " \
                 "shadow-[0_4px_24px_rgba(0,0,0,0.08)] select-none"
        ) do
          a(id:   "form-back-btn",
            href: @editing ? invoice_path(@invoice["id"]) : invoices_path,
            class: "flex items-center justify-center w-8 h-8 rounded-xl " \
                   "hover:bg-gray-100 text-gray-400 hover:text-gray-700 transition-colors flex-shrink-0") do
            span(class: "flex w-[14px] h-[14px]") { render UI::Icon.new(:chev_left, class: "w-full h-full") }
          end

          div(class: "w-px h-5 bg-gray-200 flex-shrink-0")
          p(class: "text-[13.5px] font-semibold text-gray-900 px-1") { plain @editing ? "Edit invoice" : "New invoice" }

          span(class: "text-[10.5px] font-semibold px-[8px] py-[2px] rounded-full bg-gray-100 text-gray-500") do
            plain @mode.capitalize
          end

          if @editing
            span(class: "text-[10.5px] font-semibold px-[8px] py-[2px] rounded-full flex items-center gap-[4px]",
                 style: "background:rgba(61,71,245,0.10);color:#3D47F5;border:1px solid rgba(61,71,245,0.20)") do
              span(class: "flex w-[10px] h-[10px]") { render UI::Icon.new(:edit, class: "w-full h-full") }
              plain "Editing invoice"
            end
          else
            span(class: "text-[10.5px] font-semibold px-[8px] py-[2px] rounded-full flex items-center gap-[4px]",
                 style: "background:rgba(61,71,245,0.10);color:#3D47F5;border:1px solid rgba(61,71,245,0.20)") do
              span(class: "flex w-[10px] h-[10px]") { render UI::Icon.new(:plus, class: "w-full h-full") }
              plain "New invoice"
            end
          end

          div(class: "w-px h-5 bg-gray-200 flex-shrink-0")

          if @errors.any?
            span(class: "text-[10.5px] font-semibold px-[8px] py-[2px] rounded-full bg-red-50 text-red-600") do
              plain "#{@errors.size} error#{"s" if @errors.size > 1}"
            end
          end

          if @editing
            button(
              type: "submit", form: "invoice-form",
              class: "flex items-center gap-[5px] px-[10px] py-[5px] rounded-xl text-[12.5px] font-medium " \
                     "border border-gray-200 text-gray-600 hover:bg-gray-50 transition-colors cursor-pointer border-0 bg-transparent",
              data: { action: "click->invoice-compose#saveDraft" }
            ) { plain "Save draft" }
          end

          button(
            type:  "submit",
            form:  "invoice-form",
            class: "flex items-center gap-[5px] px-[10px] py-[5px] rounded-xl text-[12.5px] font-semibold " \
                   "bg-[#3D47F5] hover:bg-[#2e38d4] text-white transition-colors cursor-pointer border-0"
          ) do
            render UI::Icon.new(:paper_plane, class: "w-3.5 h-3.5")
            plain @editing ? "Issue & update" : "Issue invoice"
          end
        end
      end

      # ── Left editor panel ────────────────────────────────────────────────────

      def editor_panel
        div(
          class: "absolute top-5 left-5 z-20 w-[340px] flex flex-col " \
                 "bg-white border border-gray-200/70 rounded-2xl overflow-hidden " \
                 "max-h-[calc(100%-40px)] " \
                 "shadow-[0_8px_32px_rgba(0,0,0,0.07),0_2px_8px_rgba(0,0,0,0.04)]"
        ) do
          div(class: "flex items-center px-4 pt-[14px] pb-[10px] flex-shrink-0") do
            p(class: "text-[11px] font-bold uppercase tracking-[0.1em] text-gray-500") { plain "Invoice" }
          end
          div(class: "h-px bg-gray-100 flex-shrink-0 mx-3")

          div(class: "flex-1 min-h-0 overflow-y-auto") do
            pdf_upload_section
            section_divider
            bill_to_section
            section_divider
            line_items_section
            section_divider
            notes_terms_section
            section_divider
            invoice_details_section
            section_divider
            send_options_section
          end
        end
      end

      def section_divider
        div(class: "h-px bg-gray-100 mx-3")
      end

      # ── PDF import ───────────────────────────────────────────────────────────

      def pdf_upload_section
        div(class: "px-4 pt-3 pb-3") do
          label(class: "flex items-center gap-2 cursor-pointer group w-full") do
            input(
              type:   "file",
              accept: ".pdf,application/pdf",
              class:  "sr-only",
              data:   { action: "change->invoice-compose#handlePdfUpload" }
            )
            div(
              class: "flex items-center gap-[7px] w-full px-3 py-[7px] rounded-xl " \
                     "border border-dashed border-gray-200 hover:border-gray-300 " \
                     "hover:bg-gray-50/60 transition-colors"
            ) do
              raw safe(<<~SVG)
                <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor"
                     stroke-width="2" stroke-linecap="round" stroke-linejoin="round"
                     class="text-gray-400 flex-shrink-0">
                  <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/>
                  <polyline points="17 8 12 3 7 8"/><line x1="12" y1="3" x2="12" y2="15"/>
                </svg>
              SVG
              span(class: "text-[12px] text-gray-500 leading-tight") { plain "Import from PDF" }
            end
          end
          p(
            class: "text-[11px] mt-1.5 leading-snug hidden",
            data:  { invoice_compose_target: "pdfStatus" }
          )
        end
      end

      # ── Bill to ──────────────────────────────────────────────────────────────

      def bill_to_section
        div(class: "px-4 pt-3 pb-4") do
          p(class: "text-[9px] font-bold uppercase tracking-[0.1em] text-gray-400 mb-2") { plain "Bill to" }
          input(
            type:        "text",
            name:        "customer_reference",
            value:       @editing ? @invoice["customer_reference"].to_s : (@prefill ? @prefill["customer_reference"].to_s : DEMO[:customer]),
            placeholder: "Company name or contact email",
            class:       panel_input_cls,
            data:        { action: "input->invoice-compose#syncPreview" }
          )
          p(class: "text-[10.5px] text-gray-400 mt-[6px] leading-snug") do
            plain "Name or email your customer is known by."
          end
        end
      end

      # ── Line items ────────────────────────────────────────────────────────────

      def line_items_section
        div(class: "px-4 pt-3 pb-4") do
          p(class: "text-[9px] font-bold uppercase tracking-[0.1em] text-gray-400 mb-3") { plain "Line items" }

          div(data: { invoice_compose_target: "rowList" }) do
            fill_rows.each_with_index do |row, i|
              div(class: "composer-sep h-px bg-gray-50 my-3") if i > 0
              editor_row(i, row)
            end
          end

          button(
            type:  "button",
            class: "mt-3 inline-flex items-center gap-1.5 text-[11.5px] font-medium text-[#3D47F5] " \
                   "hover:text-[#2e38d4] transition-colors",
            data:  { action: "click->invoice-compose#addRow" }
          ) do
            render UI::Icon.new(:plus, class: "w-3.5 h-3.5")
            plain "Add line item"
          end
        end
      end

      def editor_row(i, prefill = {})
        div(class: "composer-row group", data: { invoice_compose_target: "composerRow" }) do
          div(class: "flex items-center gap-1.5 mb-[5px]") do
            input(
              type:        "text",
              name:        "line_items[#{i}][description]",
              placeholder: "Description…",
              value:       prefill[:description].to_s,
              class:       "#{panel_input_cls} flex-1 placeholder-gray-300",
              data:        { action: "input->invoice-compose#syncPreview" }
            )
            button(
              type:  "button",
              class: "w-[26px] h-[26px] flex-shrink-0 rounded-lg flex items-center justify-center " \
                     "text-gray-200 hover:text-red-400 hover:bg-red-50 transition-colors " \
                     "opacity-0 group-hover:opacity-100",
              data:  { action: "click->invoice-compose#removeRow" }
            ) { render UI::Icon.new(:x, class: "w-3 h-3") }
          end
          div(class: "grid grid-cols-3 gap-[6px]") do
            row_subfield("Qty",        :number, "line_items[#{i}][quantity]",
                         value: prefill.fetch(:qty, 1), min: "0.01", step: "0.01")
            row_subfield("Unit price", :number, "line_items[#{i}][unit_amount]",
                         value: prefill[:unit] || "", placeholder: "0.00", min: "0", step: "0.01")
            row_subfield("Tax %",      :number, "line_items[#{i}][tax_rate_bps]",
                         value: prefill.fetch(:tax, 0), min: "0", max: "10000", step: "0.01",
                         data: { convert_bps: "true" })
          end
        end
      end

      def row_subfield(label_text, type, name, data: {}, **opts)
        label(class: "block") do
          span(class: "text-[9px] font-bold uppercase tracking-[0.1em] text-gray-400") { plain label_text }
          input(
            type:  type,
            name:  name,
            class: "#{panel_input_cls} tabular-nums text-right block w-full mt-[3px]",
            data:  { action: "input->invoice-compose#syncPreview" }.merge(data),
            **opts
          )
        end
      end

      # ── Notes & terms ─────────────────────────────────────────────────────────

      def notes_terms_section
        div(class: "px-4 pt-3 pb-4") do
          p(class: "text-[9px] font-bold uppercase tracking-[0.1em] text-gray-400 mb-2") { plain "Notes & Terms" }
          div(class: "flex flex-col gap-2") do
            textarea(
              name:        "notes",
              rows:        2,
              placeholder: "e.g. Thank you for your business.",
              class:       panel_textarea_cls,
              data:        { action: "input->invoice-compose#syncPreview" }
            ) { plain @editing ? @invoice["notes"].to_s : (@prefill ? @prefill["notes"].to_s : DEMO[:notes]) }
            textarea(
              name:        "terms",
              rows:        2,
              placeholder: "e.g. Payment due within 30 days.",
              class:       panel_textarea_cls,
              data:        { action: "input->invoice-compose#syncPreview" }
            ) { plain @editing ? @invoice["terms"].to_s : (@prefill ? @prefill["terms"].to_s : DEMO[:terms]) }
          end
        end
      end

      # ── Invoice details ───────────────────────────────────────────────────────

      def invoice_details_section
        div(class: "px-4 pt-3 pb-5") do
          p(class: "text-[9px] font-bold uppercase tracking-[0.1em] text-gray-400 mb-3") { plain "Invoice details" }
          div(class: "flex flex-col gap-2.5") do
            div do
              span(class: "text-[9px] font-bold uppercase tracking-[0.1em] text-gray-400 block mb-[5px]") { plain "Number" }
              input(type: "text", name: "number", value: @editing ? @invoice["number"].to_s : (@prefill ? @prefill["number"].to_s : ""),
                    placeholder: "INV-00001", class: panel_input_cls,
                    data: { action: "input->invoice-compose#syncPreview" })
            end

            div do
              span(class: "text-[9px] font-bold uppercase tracking-[0.1em] text-gray-400 block mb-[5px]") { plain "Currency" }
              select(name: "currency", class: "#{panel_input_cls} appearance-none cursor-pointer",
                     data: { action: "change->invoice-compose#syncPreview" }) do
                selected_currency = @editing ? @invoice["currency"] : (@prefill ? @prefill["currency"] : DEMO[:currency])
                CURRENCIES.each do |c|
                  option(value: c[:code], selected: c[:code] == selected_currency) { plain c[:label] }
                end
              end
            end

            div(class: "grid grid-cols-2 gap-2") do
              div do
                span(class: "text-[9px] font-bold uppercase tracking-[0.1em] text-gray-400 block mb-[5px]") { plain "Issue date" }
                input(type: "date", name: "issue_date",
                      value: @editing ? @invoice["issue_date"].to_s : Date.today.to_s,
                      class: panel_input_cls, data: { action: "change->invoice-compose#syncPreview" })
              end
              div do
                span(class: "text-[9px] font-bold uppercase tracking-[0.1em] text-gray-400 block mb-[5px]") { plain "Due date" }
                input(type: "date", name: "due_date",
                      value: @editing ? @invoice["due_date"].to_s : (@prefill ? (Date.today + 30).to_s : (Date.today + 30).to_s),
                      class: panel_input_cls, data: { action: "change->invoice-compose#syncPreview" })
              end
            end

            div do
              span(class: "text-[9px] font-bold uppercase tracking-[0.1em] text-gray-400 block mb-[5px]") { plain "Discount (optional)" }
              input(
                type:        "number",
                name:        "discount_amount",
                min:         "0",
                step:        "0.01",
                placeholder: "0.00",
                value:       @editing ? sprintf("%.2f", @invoice["discount_amount"].to_i / 100.0) : (@prefill ? sprintf("%.2f", @prefill["discount_amount"].to_i / 100.0) : ""),
                class:       "#{panel_input_cls} tabular-nums",
                data:        { action: "input->invoice-compose#syncPreview" }
              )
              p(class: "text-[10.5px] text-gray-400 mt-[4px]") { plain "Fixed deduction applied before the total" }
            end
          end
        end
      end

      # ── Send options ─────────────────────────────────────────────────────────

      def send_options_section
        div(class: "px-4 pt-3 pb-5") do
          p(class: "text-[9px] font-bold uppercase tracking-[0.1em] text-gray-400 mb-3") { plain "Send options" }
          div(class: "flex flex-col gap-4") do
            div do
              p(class: "text-[11px] font-semibold text-gray-600 mb-2") { plain "Accepted payment methods" }
              div(class: "flex flex-col gap-2") do
                PAYMENT_METHODS.each do |m|
                  div(class: "flex items-start gap-2") do
                    input(
                      type:    "checkbox",
                      name:    "allowed_methods[]",
                      value:   m[:value],
                      id:      "fm_method_#{m[:value]}",
                      class:   "mt-[2px] h-3.5 w-3.5 rounded border-gray-300 text-[#3D47F5] focus:ring-[#3D47F5]",
                      checked: method_checked?(m[:value])
                    )
                    div do
                      label(for: "fm_method_#{m[:value]}",
                            class: "block text-[12px] font-medium text-gray-800 cursor-pointer leading-snug") do
                        plain m[:label]
                      end
                      p(class: "text-[10.5px] text-gray-400 mt-px") { plain m[:desc] }
                    end
                  end
                end
              end
            end

            div do
              p(class: "text-[11px] font-semibold text-gray-600 mb-2") { plain "Collect from payer" }
              div(class: "flex flex-col gap-1.5") do
                fm_collect_check("collect_email", "Email address")
                fm_collect_check("collect_phone", "Phone number")
                fm_collect_check("collect_name",  "Full name")
              end
            end
          end
        end
      end

      def fm_collect_check(name, label_text)
        div(class: "flex items-center gap-2") do
          input(type: "checkbox", name: name, value: "true", id: "fm_#{name}",
                class: "h-3.5 w-3.5 rounded border-gray-300 text-[#3D47F5] focus:ring-[#3D47F5]",
                checked: collect_checked?(name))
          label(for: "fm_#{name}",
                class: "text-[12px] font-medium text-gray-700 cursor-pointer") { plain label_text }
        end
      end

      def prefill_payment_link
        @prefill&.dig("payment_link")
      end

      def method_checked?(method)
        if prefill_payment_link
          Array(prefill_payment_link["allowed_methods"]).include?(method)
        else
          method == "mobile_money"
        end
      end

      def collect_checked?(name)
        prefill_payment_link&.[](name) == true
      end

      # ── Preview area (right) ─────────────────────────────────────────────────

      def preview_area
        # Outer div is the scroll container (fixed bounds via absolute positioning).
        # Inner div centers the card and provides scroll breathing room.
        div(
          class: "absolute top-5 right-0 bottom-0 overflow-y-auto",
          style: "left: 385px"
        ) do
          div(class: "min-h-full pb-10 flex flex-col items-center") do
            invoice_preview_card
          end
        end
      end

      def invoice_preview_card
        div(
          class: "inv-preview w-full max-w-[680px] bg-white rounded-2xl overflow-hidden " \
                 "shadow-[0_12px_40px_rgba(0,0,0,0.09),0_2px_10px_rgba(0,0,0,0.05)]"
        ) do
          preview_header
          preview_billing_strip
          preview_line_items
          preview_totals
          preview_notes_terms
          preview_footer
        end
      end

      # ── Preview: header ────────────────────────────────────────────────────────

      def preview_header
        merchant_name = current_user.active_membership&.merchant_name.to_s.presence || "Your business"
        initials      = merchant_name.split.first(2).map { |w| w[0].upcase }.join

        div(class: "flex items-start justify-between px-10 pt-9 pb-6 gap-6") do
          # Left: "Invoice" title + number
          div do
            p(class: "text-[34px] font-black text-gray-900 leading-none tracking-tight") { plain "Invoice" }
            p(class: "text-[13px] text-gray-400 mt-1.5 font-mono",
              data: { invoice_compose_target: "pvNumber" }) do
              plain "#" + (@editing ? @invoice["number"].to_s : (@prefill ? "" : DEMO[:number]))
            end
          end
          # Right: logo + merchant name
          div(class: "flex items-center gap-2.5 flex-shrink-0 mt-1") do
            if @logo_url.present?
              img(src: @logo_url, alt: "Logo",
                  class: "w-10 h-10 rounded-[9px] object-cover border border-gray-100 flex-shrink-0")
            else
              div(class: "w-10 h-10 rounded-[9px] bg-[#3D47F5] flex items-center justify-center flex-shrink-0") do
                span(class: "text-[11px] font-extrabold text-white tracking-tight") { plain initials }
              end
            end
            p(class: "text-[15px] font-bold text-gray-900 leading-tight") { plain merchant_name }
          end
        end
      end

      # ── Preview: billing strip ────────────────────────────────────────────────

      def preview_billing_strip
        merchant_name = current_user.active_membership&.merchant_name.to_s.presence || "Your business"
        bill_to_value = @editing ? @invoice["customer_reference"].to_s
                      : (@prefill  ? @prefill["customer_reference"].to_s
                                   : DEMO[:customer])

        # ── Divider 1
        div(class: "h-px bg-gray-100 mx-10")

        # ── Bill to / dates
        div(class: "flex items-start justify-between px-10 py-5") do
          div do
            p(class: "text-[9.5px] font-semibold uppercase tracking-[0.1em] text-gray-400 mb-[5px]") { plain "Bill to" }
            p(class: "text-[13.5px] font-semibold text-gray-900",
              data: { invoice_compose_target: "pvBillTo" }) { plain bill_to_value.presence || "—" }
          end
          div(class: "flex items-start gap-7") do
            div(class: "text-right") do
              p(class: "text-[9.5px] font-semibold uppercase tracking-[0.1em] text-gray-400 mb-[5px]") { plain "Issued Date" }
              p(class: "text-[13.5px] font-semibold text-gray-900",
                data: { invoice_compose_target: "pvIssued" }) { plain fmt_date(Date.today) }
            end
            div(class: "text-right") do
              p(class: "text-[9.5px] font-semibold uppercase tracking-[0.1em] text-gray-400 mb-[5px]") { plain "Due Date" }
              p(class: "text-[13.5px] font-semibold text-gray-900",
                data: { invoice_compose_target: "pvDue" }) { plain fmt_date(Date.today + 30) }
            end
          end
        end

        # ── Divider 2
        div(class: "h-px bg-gray-100 mx-10")

        # ── From / To
        div(class: "flex items-start justify-between px-10 py-5") do
          div do
            p(class: "text-[9.5px] font-semibold uppercase tracking-[0.1em] text-gray-400 mb-[5px]") { plain "From" }
            p(class: "text-[13px] font-semibold text-gray-900 leading-snug") { plain merchant_name }
          end
          div(class: "text-right") do
            p(class: "text-[9.5px] font-semibold uppercase tracking-[0.1em] text-gray-400 mb-[5px]") { plain "To" }
            p(class: "text-[13px] font-semibold text-gray-900 leading-snug") do
              plain bill_to_value.presence || "—"
            end
          end
        end
      end

      # ── Preview: line items table ─────────────────────────────────────────────

      def preview_line_items
        div(class: "overflow-x-auto mx-6") do
          table(class: "w-full") do
            thead do
              tr(style: "background:#f9fafb;border-bottom:1px solid #f1f5f9") do
                th_cell("Description", "text-left pl-5 pr-3")
                th_cell("Qty",         "text-right px-3 w-14")
                th_cell("Unit price",  "text-right px-3 w-28")
                th_cell("Tax",         "text-right px-3 w-16")
                th_cell("Amount",      "text-right pl-3 pr-5 w-32")
              end
            end
            tbody(data: { invoice_compose_target: "pvRowsBody" }) do
              # Two pre-rendered demo rows matching DEMO[:rows]
              DEMO[:rows].each do |row|
                unit_cents = (row[:unit] * 100).round
                amount = unit_cents * row[:qty]
                preview_static_row(
                  row[:description],
                  row[:qty].to_s,
                  "GH₵ #{sprintf('%.2f', row[:unit])}",
                  row[:tax] > 0 ? "#{row[:tax]}%" : "—",
                  "GH₵ #{fmt_num(amount.to_i)}"
                )
              end
            end
          end
        end
      end

      def preview_static_row(desc, qty, unit, tax, amount)
        tr(class: "border-b border-gray-50 last:border-0") do
          td(class: "pl-5 pr-3 py-3.5 text-[12.5px] text-gray-800") { plain desc }
          td(class: "px-3 py-3.5 text-right text-[12px] text-gray-400 tabular-nums") { plain qty }
          td(class: "px-3 py-3.5 text-right text-[12px] text-gray-400 tabular-nums") { plain unit }
          td(class: "px-3 py-3.5 text-right text-[12px] text-gray-400 tabular-nums") { plain tax }
          td(class: "pl-3 pr-5 py-3.5 text-right text-[12.5px] font-semibold text-gray-900 tabular-nums") { plain amount }
        end
      end

      def th_cell(text, extra_cls)
        th(class: "py-2.5 #{extra_cls} text-[9px] font-bold uppercase tracking-[0.1em] text-gray-400") { plain text }
      end

      # ── Preview: totals ───────────────────────────────────────────────────────

      def preview_totals
        demo_subtotal = DEMO[:rows].sum { |r| (r[:unit] * 100 * r[:qty]).round }

        div(class: "h-px bg-gray-100 mx-6")
        div(class: "flex justify-end px-10 py-6") do
          div(class: "w-[280px] flex flex-col gap-[2px]") do
            totals_row("Subtotal", :pvSubtotal, default: "GH₵ #{fmt_num(demo_subtotal)}")
            div(class: "flex items-center justify-between py-[2px]",
                hidden: true, data: { invoice_compose_target: "pvTaxRow" }) do
              p(class: "text-[12px] text-gray-400") { plain "Tax" }
              p(class: "text-[12.5px] text-gray-500 tabular-nums",
                data: { invoice_compose_target: "pvTax" }) { plain "GH₵ 0.00" }
            end
            div(class: "flex items-center justify-between py-[2px]",
                hidden: true, data: { invoice_compose_target: "pvDiscountRow" }) do
              p(class: "text-[12px] text-gray-400") { plain "Discount" }
              p(class: "text-[12.5px] text-green-600 tabular-nums",
                data: { invoice_compose_target: "pvDiscount" }) { plain "− GH₵ 0.00" }
            end
            div(class: "h-px bg-gray-200 my-2")
            # Bold "Total Amount" row — matching screenshot
            div(class: "flex items-center justify-between py-[3px]") do
              p(class: "text-[13.5px] font-bold text-gray-900") { plain "Total Amount" }
              p(class: "text-[14px] font-bold text-gray-900 tabular-nums",
                data: { invoice_compose_target: "pvTotal" }) do
                plain "GH₵ #{fmt_num(demo_subtotal)}"
              end
            end
            # Amount due (subtle subtitle row; JS keeps it in sync)
            div(class: "flex items-center justify-between pt-[2px]") do
              p(class: "text-[11px] text-gray-400") { plain "Amount due" }
              p(class: "text-[12px] font-semibold text-[#3D47F5] tabular-nums",
                data: { invoice_compose_target: "pvAmountDue" }) do
                plain "GH₵ #{fmt_num(demo_subtotal)}"
              end
            end
          end
        end
      end

      def totals_row(label, target_sym, bold: false, default: "GH₵ 0.00")
        div(class: "flex items-center justify-between py-[2px]") do
          p(class: "text-[12px] #{bold ? 'font-semibold text-gray-700' : 'text-gray-400'}") { plain label }
          p(class: "text-[12.5px] #{bold ? 'font-semibold text-gray-900' : 'text-gray-500'} tabular-nums",
            data: { invoice_compose_target: target_sym }) { plain default }
        end
      end

      # ── Preview: notes / terms ────────────────────────────────────────────────

      def preview_notes_terms
        div(
          class: "px-10 pb-7 flex flex-col gap-5",
          data:  { invoice_compose_target: "pvNotesTermsSection" }
        ) do
          div(data: { invoice_compose_target: "pvNotesSection" }) do
            div(class: "border border-gray-200 rounded-xl px-5 py-4") do
              p(class: "text-[12.5px] text-gray-600 leading-relaxed",
                data: { invoice_compose_target: "pvNotes" }) { plain DEMO[:notes] }
            end
          end
          div(data: { invoice_compose_target: "pvTermsSection" }) do
            p(class: "text-[9.5px] font-bold uppercase tracking-[0.12em] text-gray-400 mb-1.5") { plain "Terms & conditions" }
            p(class: "text-[12.5px] text-gray-600 leading-relaxed",
              data: { invoice_compose_target: "pvTerms" }) { plain DEMO[:terms] }
          end
        end
      end

      # ── Preview: footer ───────────────────────────────────────────────────────

      def preview_footer
        div(class: "border-t border-gray-100 px-10 py-4 flex items-center justify-between") do
          div do
            p(class: "text-[9.5px] font-bold uppercase tracking-[0.1em] text-gray-400 mb-[3px]") { plain "Payment method" }
            p(class: "text-[11px] text-gray-400") { plain "Payment powered by Yagye" }
          end
          p(class: "text-[10.5px] text-gray-300") { plain fmt_date(Date.today) }
        end
      end

      # ── Edit-mode helpers ─────────────────────────────────────────────────────

      def fill_rows
        source = @editing ? @invoice : @prefill
        if source
          rows = Array(source["line_items"]).map do |li|
            {
              description: li["description"].to_s,
              qty:         li["quantity"].to_f,
              unit:        li["unit_amount"].to_f / 100.0,
              tax:         li["tax_rate_bps"].to_i
            }
          end
          rows.any? ? rows : DEMO[:rows]
        else
          DEMO[:rows]
        end
      end

      # ── Back button script ────────────────────────────────────────────────────

      def back_btn_script
        script(nonce: content_security_policy_nonce) do
          raw safe(<<~JS)
            (function () {
              var btn = document.getElementById('form-back-btn');
              if (!btn) return;
              btn.addEventListener('click', function (e) {
                if (history.length > 1) {
                  e.preventDefault();
                  history.back();
                }
              });
            })();
          JS
        end
      end

      # ── Shared input styles ───────────────────────────────────────────────────

      def panel_input_cls
        "w-full h-[34px] border border-gray-200 rounded-[9px] px-2.5 text-[12.5px] " \
        "text-gray-700 bg-white outline-none focus:border-[#3D47F5] transition-colors"
      end

      def panel_textarea_cls
        "w-full border border-gray-200 rounded-[9px] px-2.5 py-2 text-[12.5px] " \
        "text-gray-700 bg-white outline-none focus:border-[#3D47F5] transition-colors resize-none"
      end
    end
  end
end
