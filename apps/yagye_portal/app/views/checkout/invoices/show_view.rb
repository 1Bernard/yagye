# frozen_string_literal: true

module Checkout
  module Invoices
    class ShowView < ApplicationComponent
      include UI::Theme

      PAYMENT_METHODS = [
        { value: "mobile_money",  label: "Mobile Money",  desc: "MTN MoMo, Telecel Cash, AirtelTigo" },
        { value: "card",          label: "Card",           desc: "Visa and Mastercard" },
        { value: "bank_transfer", label: "Bank transfer",  desc: "Direct bank-to-bank transfers" }
      ].freeze

      def initialize(invoice:)
        @inv = invoice
      end

      def view_template
        render Layout::Shell.new(
          active_nav: :invoices,
          title:      @inv["number"] || @inv["id"],
          padded:     false
        ) do
          style { raw safe(canvas_css) }
          div(id: "inv-show-canvas",
              class: "relative w-full overflow-hidden",
              style: "height: calc(100vh - 56px)") do
            floating_toolbar
            div(class: "absolute top-[76px] left-0 right-0 bottom-0") do
              left_panel
              right_area
            end
          end
          copy_script if checkout_url.present?
        end
      end

      private

      # ── Canvas ───────────────────────────────────────────────────────────────

      def canvas_css
        <<~CSS
          #inv-show-canvas {
            background-color: #f8fafc;
            background-image: radial-gradient(circle at 1px 1px, #d1d5db 1px, transparent 0);
            background-size: 24px 24px;
          }
        CSS
      end

      # ── Floating toolbar ─────────────────────────────────────────────────────

      def floating_toolbar
        state = @inv["state"]

        div(
          class: "absolute top-4 left-1/2 -translate-x-1/2 z-30 flex items-center gap-[6px] " \
                 "bg-white border border-gray-200/80 rounded-2xl px-[10px] py-[7px] " \
                 "shadow-[0_4px_24px_rgba(0,0,0,0.08)] select-none"
        ) do
          a(href: invoices_path,
            class: "flex items-center justify-center w-8 h-8 rounded-xl " \
                   "hover:bg-gray-100 text-gray-400 hover:text-gray-700 transition-colors flex-shrink-0") do
            span(class: "flex w-[14px] h-[14px]") { render UI::Icon.new(:chev_left, class: "w-full h-full") }
          end

          toolbar_divider

          p(class: "text-[13.5px] font-semibold text-gray-900 px-1 max-w-[200px] truncate") do
            plain @inv["number"] || @inv["id"].to_s.first(12)
          end

          toolbar_state_badge(state)

          span(class: "text-[10.5px] font-semibold px-[8px] py-[2px] rounded-full bg-gray-100 text-gray-500") do
            plain (@inv["mode"] || "simulation").capitalize
          end

          toolbar_divider

          if state == "draft"
            a(href: edit_invoice_path(@inv["id"]),
              class: "flex items-center gap-[5px] px-[10px] py-[5px] rounded-xl text-[12.5px] font-medium " \
                     "border border-gray-200 text-gray-600 hover:bg-gray-50 transition-colors no-underline") do
              render UI::Icon.new(:edit, class: "w-3.5 h-3.5 text-gray-400")
              plain "Edit"
            end
          end

          if checkout_url.present? && state != "draft"
            a(href: checkout_url, target: "_blank", rel: "noopener noreferrer",
              class: "flex items-center gap-[5px] px-[10px] py-[5px] rounded-xl text-[12.5px] font-semibold " \
                     "bg-[#3D47F5] hover:bg-[#2e38d4] text-white transition-colors no-underline") do
              render UI::Icon.new(:arrow_right, class: "w-3.5 h-3.5")
              plain "Open"
            end
          end

          if %w[open partially_paid overdue].include?(state)
            toolbar_divider
            form(action: void_invoice_path(@inv["id"]), method: "post", style: "display:contents") do
              input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
              button(
                type:  "submit",
                class: "flex items-center gap-[5px] px-[10px] py-[5px] rounded-xl text-[12.5px] font-medium " \
                       "border border-red-200 text-red-600 hover:bg-red-50 transition-colors cursor-pointer",
                data:  { confirm: "Void this invoice? This cannot be undone." }
              ) do
                render UI::Icon.new(:x, class: "w-3.5 h-3.5")
                plain "Void"
              end
            end
          end

          if state == "void"
            toolbar_divider
            a(
              href:  duplicate_invoice_path(@inv["id"]),
              class: "flex items-center gap-[5px] px-[10px] py-[5px] rounded-xl text-[12.5px] font-medium " \
                     "border border-gray-200 text-gray-600 hover:bg-gray-50 transition-colors no-underline"
            ) do
              render UI::Icon.new(:file, class: "w-3.5 h-3.5")
              plain "Duplicate"
            end
          end
        end
      end

      def toolbar_divider
        div(class: "w-px h-5 bg-gray-200 flex-shrink-0")
      end

      def toolbar_state_badge(state)
        render UI::StatusBadge.new(status: state)
      end

      # ── Left panel ───────────────────────────────────────────────────────────

      def left_panel
        div(class: "absolute top-5 left-5 bottom-5 w-[340px] overflow-y-auto " \
                   "bg-white/80 backdrop-blur-sm border border-white/60 rounded-2xl " \
                   "shadow-[0_8px_32px_rgba(0,0,0,0.08),0_2px_8px_rgba(0,0,0,0.04)]") do
          div(class: "p-5 flex flex-col gap-4") do
            panel_header
            customer_section
            panel_divider
            details_section
            panel_divider
            amounts_section

            if @inv["state"] == "draft"
              panel_divider
              issue_section
            end

            if checkout_url.present? && @inv["state"] != "draft"
              panel_divider
              link_section
            end

            if @inv["notes"].present? || @inv["terms"].present?
              panel_divider
              notes_section
            end
          end
        end
      end

      def panel_header
        div do
          p(class: "text-[10px] font-bold tracking-[0.15em] uppercase text-[#3D47F5] mb-0.5") do
            plain "Invoice"
          end
          p(class: "text-[18px] font-bold text-gray-900 leading-tight truncate") do
            plain @inv["number"] || @inv["id"].to_s.first(16)
          end
        end
      end

      def customer_section
        div(class: "flex flex-col gap-1") do
          p(class: "text-[10px] font-bold uppercase tracking-[0.12em] text-gray-400") { plain "Bill to" }
          if @inv["customer_reference"].present?
            p(class: "text-[13px] font-semibold text-gray-800 leading-snug") do
              plain @inv["customer_reference"]
            end
          else
            p(class: "text-[12.5px] text-gray-400 italic") { plain "No customer reference" }
          end
          p(class: "text-[11px] text-gray-400 mt-0.5") do
            plain "via #{@inv["merchant_code"] || "—"}"
          end
        end
      end

      def details_section
        div(class: "flex flex-col gap-2") do
          p(class: "text-[10px] font-bold uppercase tracking-[0.12em] text-gray-400 mb-1") { plain "Details" }
          detail_row("Number",    @inv["number"] || "—",         mono: true)
          detail_row("Currency",  @inv["currency"] || "—")
          detail_row("Issue date", fmt_date(@inv["issue_date"]))
          detail_row("Due date",  fmt_date(@inv["due_date"]))
          detail_row("Sent",      fmt_datetime(@inv["sent_at"]))      if @inv["sent_at"].present?
          detail_row("Paid at",   fmt_datetime(@inv["paid_at"]))      if @inv["paid_at"].present?
          detail_row("Voided at", fmt_datetime(@inv["voided_at"]))    if @inv["voided_at"].present?
          detail_row("Created",   fmt_datetime(@inv["inserted_at"]))
        end
      end

      def detail_row(label, value, mono: false)
        div(class: "flex items-start justify-between gap-2") do
          p(class: "text-[11.5px] text-gray-400 flex-shrink-0") { plain label }
          p(class: "text-[11.5px] #{mono ? 'font-mono' : 'font-medium'} text-gray-700 text-right leading-snug") do
            plain value || "—"
          end
        end
      end

      def amounts_section
        subtotal   = @inv["subtotal_amount"].to_i
        tax        = @inv["tax_amount"].to_i
        discount   = @inv["discount_amount"].to_i
        total      = @inv["total_amount"].to_i
        amount_due = @inv["amount_due"].to_i
        paid       = @inv["amount_paid"].to_i

        div(class: "flex flex-col gap-1.5") do
          p(class: "text-[10px] font-bold uppercase tracking-[0.12em] text-gray-400 mb-1") { plain "Amounts" }
          amt_row("Subtotal", format_money(subtotal))
          amt_row("Tax",      format_money(tax))             if tax > 0
          amt_row("Discount", "− #{format_money(discount)}") if discount > 0
          amt_row("Total",    format_money(total), bold: true)
          amt_row("Paid",     "− #{format_money(paid)}", color: "text-green-600") if paid > 0

          div(class: "mt-2 flex items-center justify-between rounded-xl " \
                     "bg-[#3D47F5]/[0.07] px-3 py-2.5") do
            p(class: "text-[11.5px] font-bold text-[#3D47F5]") { plain "Amount due" }
            p(class: "text-[14px] font-bold text-[#3D47F5] tabular-nums") do
              plain format_money(amount_due)
            end
          end
        end
      end

      def amt_row(label, value, bold: false, color: "text-gray-600")
        div(class: "flex items-center justify-between") do
          p(class: "text-[11.5px] #{bold ? 'font-semibold text-gray-700' : 'text-gray-400'}") { plain label }
          p(class: "text-[11.5px] #{bold ? 'font-semibold text-gray-800' : color} tabular-nums") { plain value }
        end
      end

      # ── Issue form ───────────────────────────────────────────────────────────

      def issue_section
        div(class: "flex flex-col gap-3") do
          p(class: "text-[10px] font-bold uppercase tracking-[0.12em] text-gray-400") { plain "Issue invoice" }

          form(action: issue_invoice_path(@inv["id"]), method: "post") do
            input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)

            div(class: "flex flex-col gap-3") do
              div do
                p(class: "text-[11px] font-semibold text-gray-600 mb-2") { plain "Accepted payment methods" }
                div(class: "flex flex-col gap-2") do
                  PAYMENT_METHODS.each_with_index do |m, i|
                    div(class: "flex items-start gap-2") do
                      input(
                        type:    "checkbox",
                        name:    "allowed_methods[]",
                        value:   m[:value],
                        id:      "inv_method_#{m[:value]}",
                        class:   "mt-[2px] h-3.5 w-3.5 rounded border-gray-300 text-[#3D47F5] focus:ring-[#3D47F5]",
                        checked: i == 0
                      )
                      div do
                        label(for: "inv_method_#{m[:value]}",
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
                  collect_check("collect_email", "Email address")
                  collect_check("collect_phone", "Phone number")
                  collect_check("collect_name",  "Full name")
                end
              end

              button(type: "submit",
                     class: "w-full flex items-center justify-center gap-2 h-9 px-4 mt-1 " \
                            "bg-[#3D47F5] text-white rounded-[10px] text-[12.5px] font-semibold " \
                            "hover:bg-[#3340e0] transition-colors") do
                render UI::Icon.new(:paper_plane, class: "w-3.5 h-3.5")
                plain "Issue & share invoice"
              end
            end
          end
        end
      end

      def collect_check(name, label_text)
        div(class: "flex items-center gap-2") do
          input(type:  "checkbox", name: name, value: "true", id: "inv_#{name}",
                class: "h-3.5 w-3.5 rounded border-gray-300 text-[#3D47F5] focus:ring-[#3D47F5]")
          label(for:   "inv_#{name}",
                class: "text-[12px] font-medium text-gray-700 cursor-pointer") { plain label_text }
        end
      end

      # ── Payment link section ──────────────────────────────────────────────────

      def link_section
        url = checkout_url

        div(class: "flex flex-col gap-2") do
          p(class: "text-[10px] font-bold uppercase tracking-[0.12em] text-gray-400") { plain "Invoice link" }

          div(class: "flex items-center gap-2 bg-gray-50 border border-gray-200 " \
                     "rounded-xl px-3 py-2 overflow-hidden") do
            span(class: "flex-shrink-0 text-gray-400") do
              render UI::Icon.new(:link, class: "w-3.5 h-3.5")
            end
            p(class: "font-mono text-[10.5px] text-gray-600 truncate flex-1",
              id:    "inv-checkout-url",
              data:  { url: url }) { plain url }
          end

          div(class: "flex gap-2") do
            button(
              type:  "button",
              id:    "copy-inv-url-btn",
              class: "flex-1 flex items-center justify-center gap-1.5 h-8 px-3 " \
                     "border border-gray-200 rounded-[8px] text-[11.5px] font-medium " \
                     "text-gray-600 hover:border-gray-300 hover:bg-gray-50 transition-colors"
            ) do
              render UI::Icon.new(:copy, class: "w-3.5 h-3.5 text-gray-400")
              plain "Copy link"
            end
            a(href:   url, target: "_blank", rel: "noopener noreferrer",
              class:  "flex items-center justify-center gap-1.5 h-8 px-3 " \
                      "border border-gray-200 rounded-[8px] text-[11.5px] font-medium " \
                      "text-gray-600 hover:border-gray-300 hover:bg-gray-50 transition-colors") do
              render UI::Icon.new(:arrow_right, class: "w-3.5 h-3.5 text-gray-400")
              plain "Open"
            end
          end
        end
      end

      def copy_script
        script do
          raw safe(<<~JS)
            (function () {
              var urlEl = document.getElementById('inv-checkout-url');
              if (!urlEl) return;
              var url = urlEl.dataset.url;
              var btn = document.getElementById('copy-inv-url-btn');
              if (!btn) return;
              btn.addEventListener('click', function () {
                navigator.clipboard.writeText(url).then(function () {
                  btn.textContent = 'Copied!';
                  setTimeout(function () {
                    btn.innerHTML = '<svg class="w-3.5 h-3.5 text-gray-400" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg>Copy link';
                  }, 2000);
                });
              });
            })();
          JS
        end
      end

      # ── Notes / Terms section ─────────────────────────────────────────────────

      def notes_section
        div(class: "flex flex-col gap-3") do
          if @inv["notes"].present?
            div do
              p(class: "text-[10px] font-bold uppercase tracking-[0.12em] text-gray-400 mb-1") { plain "Notes" }
              p(class: "text-[12px] text-gray-600 leading-relaxed") { plain @inv["notes"] }
            end
          end
          if @inv["terms"].present?
            div do
              p(class: "text-[10px] font-bold uppercase tracking-[0.12em] text-gray-400 mb-1") { plain "Terms & conditions" }
              p(class: "text-[12px] text-gray-600 leading-relaxed") { plain @inv["terms"] }
            end
          end
        end
      end

      def panel_divider
        div(class: "border-t border-gray-100")
      end

      # ── Right area: invoice document ──────────────────────────────────────────

      def right_area
        div(class: "absolute top-5 right-0 bottom-0 overflow-y-auto",
            style: "left: 385px") do
          div(class: "min-h-full flex flex-col items-center justify-start py-10 px-6") do
            div(class: "w-full max-w-[680px] bg-white rounded-2xl overflow-hidden " \
                       "shadow-[0_8px_40px_rgba(0,0,0,0.10),0_2px_12px_rgba(0,0,0,0.06)]") do
              document_header
              status_banner
              from_to_section
              document_divider
              line_items_section
              totals_section
              notes_footer if @inv["notes"].present? || @inv["terms"].present?
            end
          end
        end
      end

      # ── Invoice document ──────────────────────────────────────────────────────

      def document_header
        div(class: "flex items-start justify-between px-10 pt-9 pb-7 border-b border-gray-100") do
          div do
            p(class: "text-[11px] font-bold tracking-[0.18em] uppercase text-[#3D47F5] mb-1") do
              plain "Invoice"
            end
            p(class: "text-[28px] font-bold text-gray-900 leading-none") do
              plain @inv["number"] || @inv["id"].to_s.first(12)
            end
          end
          div(class: "flex flex-col items-end gap-3") do
            state_badge(@inv["state"])
            div(class: "grid grid-cols-2 gap-x-8 gap-y-1 text-right") do
              doc_date_cell("Issued", @inv["issue_date"])
              doc_date_cell("Due",    @inv["due_date"])
            end
          end
        end
      end

      def doc_date_cell(label, value)
        p(class: "text-[10.5px] font-semibold uppercase tracking-wide text-gray-400") { plain label }
        p(class: "text-[12.5px] font-medium text-gray-800") do
          plain value ? (Date.parse(value) rescue value).then { |d| d.respond_to?(:strftime) ? d.strftime("%d %b %Y") : d } : "—"
        end
      end

      def status_banner
        state = @inv["state"]
        return unless %w[overdue paid void].include?(state)

        cfg = case state
              when "overdue" then { bg: "bg-red-50 border-red-100",    text: "text-red-700",   msg: "This invoice is overdue." }
              when "paid"    then { bg: "bg-green-50 border-green-100", text: "text-green-700", msg: "Payment received in full." }
              when "void"    then { bg: "bg-gray-50 border-gray-200",   text: "text-gray-500",  msg: "This invoice has been voided." }
              end

        div(class: "px-10 py-3 border-b #{cfg[:bg]} #{cfg[:text]} text-[12px] font-medium flex items-center justify-between gap-4") do
          plain cfg[:msg]
          if state == "void"
            a(
              href:  duplicate_invoice_path(@inv["id"]),
              class: "text-[11.5px] font-semibold px-3 py-1 rounded-lg border border-gray-300 " \
                     "text-gray-600 bg-white hover:bg-gray-50 transition-colors no-underline flex-shrink-0"
            ) { plain "Duplicate" }
          end
        end
      end

      def from_to_section
        merchant_name = current_user.active_membership&.merchant_name.to_s.presence || "Your business"

        div(class: "grid grid-cols-2 gap-8 px-10 py-7") do
          div do
            p(class: "text-[10.5px] font-bold uppercase tracking-[0.12em] text-gray-400 mb-2") { plain "From" }
            p(class: "text-[13px] font-semibold text-gray-800 leading-snug") { plain merchant_name }
            p(class: "text-[12px] text-gray-400 mt-0.5") { plain current_user.merchant_code || "—" }
          end
          div do
            p(class: "text-[10.5px] font-bold uppercase tracking-[0.12em] text-gray-400 mb-2") { plain "Bill to" }
            if @inv["customer_reference"].present?
              p(class: "text-[13px] font-semibold text-gray-800 leading-snug") do
                plain @inv["customer_reference"]
              end
            else
              p(class: "text-[12.5px] text-gray-400 italic") { plain "No customer reference" }
            end
          end
        end
      end

      def document_divider
        div(class: "mx-10 border-t border-dashed border-gray-200")
      end

      def line_items_section
        items    = Array(@inv["line_items"])
        currency = @inv["currency"] || "GHS"

        div(class: "overflow-x-auto") do
          table(class: "w-full") do
            thead do
              tr(class: "border-b border-gray-100") do
                th(class: "text-left px-10 py-3 text-[10.5px] font-bold uppercase tracking-[0.1em] text-gray-400") { plain "Description" }
                th(class: "text-right px-4 py-3 text-[10.5px] font-bold uppercase tracking-[0.1em] text-gray-400")  { plain "Qty" }
                th(class: "text-right px-4 py-3 text-[10.5px] font-bold uppercase tracking-[0.1em] text-gray-400")  { plain "Unit price" }
                th(class: "text-right px-4 py-3 text-[10.5px] font-bold uppercase tracking-[0.1em] text-gray-400")  { plain "Tax" }
                th(class: "text-right px-10 py-3 text-[10.5px] font-bold uppercase tracking-[0.1em] text-gray-400") { plain "Amount" }
              end
            end
            tbody do
              items.each_with_index do |item, idx|
                unit    = item["unit_amount"].to_i
                qty     = item["quantity"].to_f
                bps     = item["tax_rate_bps"].to_i
                amount  = (unit * qty + unit * qty * bps / 10_000.0).round
                row_cls = idx.odd? ? "bg-gray-50/60" : "bg-white"

                tr(class: "#{row_cls} border-b border-gray-50 last:border-0") do
                  td(class: "px-10 py-3.5 text-[13px] text-gray-800") { plain item["description"] || "—" }
                  td(class: "px-4 py-3.5 text-right text-[12.5px] text-gray-500 tabular-nums") do
                    plain qty % 1 == 0 ? qty.to_i.to_s : "%.2f" % qty
                  end
                  td(class: "px-4 py-3.5 text-right text-[12.5px] text-gray-500 tabular-nums") do
                    plain "#{currency} #{"%.2f" % (unit / 100.0)}"
                  end
                  td(class: "px-4 py-3.5 text-right text-[12.5px] text-gray-500 tabular-nums") do
                    plain bps > 0 ? "#{bps / 100.0}%" : "—"
                  end
                  td(class: "px-10 py-3.5 text-right text-[13px] font-semibold text-gray-900 tabular-nums") do
                    plain "#{currency} #{"%.2f" % (amount / 100.0)}"
                  end
                end
              end
            end
          end
        end
      end

      def totals_section
        subtotal   = @inv["subtotal_amount"].to_i
        tax        = @inv["tax_amount"].to_i
        discount   = @inv["discount_amount"].to_i
        total      = @inv["total_amount"].to_i
        amount_due = @inv["amount_due"].to_i
        paid       = @inv["amount_paid"].to_i

        div(class: "flex justify-end border-t border-gray-100 px-10 py-6") do
          div(class: "w-72 flex flex-col gap-[3px]") do
            totals_row("Subtotal", format_money(subtotal))
            totals_row("Tax",      format_money(tax))             if tax > 0
            totals_row("Discount", "− #{format_money(discount)}") if discount > 0
            totals_row("Total",    format_money(total), bold: true)
            totals_row("Paid",     "− #{format_money(paid)}", color: "text-green-600") if paid > 0
            div(class: "mt-3 flex items-center justify-between rounded-xl " \
                       "bg-[#3D47F5]/[0.06] px-4 py-3.5") do
              p(class: "text-[12px] font-bold text-[#3D47F5]") { plain "Amount due" }
              p(class: "text-[16px] font-bold text-[#3D47F5] tabular-nums") do
                plain format_money(amount_due)
              end
            end
          end
        end
      end

      def totals_row(label, value, bold: false, color: "text-gray-600")
        div(class: "flex items-center justify-between py-[2px]") do
          p(class: "text-[12px] #{bold ? 'font-semibold text-gray-800' : 'text-gray-400'}") { plain label }
          p(class: "text-[12.5px] #{bold ? 'font-semibold text-gray-900' : color} tabular-nums") { plain value }
        end
      end

      def notes_footer
        div(class: "border-t border-dashed border-gray-200 mx-10 mt-1")
        div(class: "px-10 py-7 grid gap-4 " \
                   "#{@inv['notes'].present? && @inv['terms'].present? ? 'grid-cols-2' : 'grid-cols-1'}") do
          if @inv["notes"].present?
            div do
              p(class: "text-[10.5px] font-bold uppercase tracking-[0.1em] text-gray-400 mb-1.5") { plain "Notes" }
              p(class: "text-[12.5px] text-gray-600 leading-relaxed") { plain @inv["notes"] }
            end
          end
          if @inv["terms"].present?
            div do
              p(class: "text-[10.5px] font-bold uppercase tracking-[0.1em] text-gray-400 mb-1.5") { plain "Terms & conditions" }
              p(class: "text-[12.5px] text-gray-600 leading-relaxed") { plain @inv["terms"] }
            end
          end
        end
      end

      # ── Helpers ──────────────────────────────────────────────────────────────

      def state_badge(state)
        render UI::StatusBadge.new(status: state)
      end

      def format_money(minor_units, currency: @inv["currency"] || "GHS")
        "#{currency} #{"%.2f" % (minor_units / 100.0)}"
      end

      def checkout_url
        @inv["invoice_view_url"] || @inv["payment_link_checkout_url"]
      end

      def fmt_date(val)
        return "—" unless val.present?
        (Date.parse(val) rescue val).then { |d| d.respond_to?(:strftime) ? d.strftime("%d %b %Y") : d }
      end

      def fmt_datetime(val)
        return "—" unless val.present?
        (Time.parse(val) rescue val).then { |t| t.respond_to?(:strftime) ? t.strftime("%d %b %Y at %H:%M") : t }
      end
    end
  end
end
