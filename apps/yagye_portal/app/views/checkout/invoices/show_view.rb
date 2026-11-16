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

      def initialize(invoice:, logo_url: nil)
        @inv      = invoice
        @logo_url = logo_url
      end

      def view_template
        render Layout::Shell.new(
          active_nav:   :invoices,
          title:        @inv["number"] || @inv["id"],
          padded:       false,
          hide_sidebar: true,
          hide_topbar:  true
        ) do
          style { raw safe(canvas_css) }
          div(id: "inv-show-canvas",
              class: "relative w-full overflow-hidden",
              style: "height: 100vh") do
            floating_toolbar
            div(id: "inv-show-wrap", class: "absolute top-[76px] left-0 right-0 bottom-0") do
              left_panel
              right_area
            end
          end
          copy_script if checkout_url.present?
          print_script
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
          @page { size: auto; margin: 15mm; }
          @media print {
            .inv-no-print { display: none !important; }
            #inv-show-canvas { background: none; position: static; height: auto; overflow: visible; }
            #inv-show-wrap   { position: static; height: auto; overflow: visible; }
            .inv-right-area  { position: static; left: auto; top: auto; overflow: visible; padding: 0; }
            .inv-doc-card    { box-shadow: none; border: 1px solid #e5e7eb; width: 100%; max-width: 100%; }
          }
        CSS
      end

      # ── Floating toolbar ─────────────────────────────────────────────────────

      def floating_toolbar
        state = @inv["state"]

        div(
          class: "absolute top-4 left-1/2 -translate-x-1/2 z-30 flex items-center gap-[6px] " \
                 "bg-white border border-gray-200/80 rounded-2xl px-[10px] py-[7px] " \
                 "shadow-[0_4px_24px_rgba(0,0,0,0.08)] select-none inv-no-print"
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

          span(class: "#{BADGE_XS} #{STATUS_NEUTRAL}") do
            plain (@inv["mode"] || "simulation").capitalize
          end

          button(
            type:  "button",
            id:    "inv-print-btn",
            class: "flex items-center gap-[5px] px-[10px] py-[5px] rounded-xl text-[12.5px] font-medium " \
                   "text-gray-600 hover:bg-gray-50 transition-colors cursor-pointer border-0 bg-transparent"
          ) do
            render UI::Icon.new(:printer, class: "w-3.5 h-3.5 text-gray-400")
            plain "Print"
          end

          toolbar_divider

          if state == "draft"
            a(href: edit_invoice_path(@inv["id"]),
              class: "flex items-center gap-[5px] px-[10px] py-[5px] rounded-xl text-[12.5px] font-medium " \
                     "border border-gray-200 text-gray-600 hover:bg-gray-50 transition-colors no-underline") do
              render UI::Icon.new(:edit, class: "w-3.5 h-3.5 text-gray-400")
              plain "Edit"
            end

            form(action: issue_invoice_path(@inv["id"]), method: "post", style: "display:contents") do
              input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
              input(type: "hidden", name: "allowed_methods[]",  value: "mobile_money")
              button(
                type:  "submit",
                class: "flex items-center gap-[5px] px-[10px] py-[5px] rounded-xl text-[12.5px] font-semibold " \
                       "bg-[#3D47F5] hover:bg-[#2e38d4] text-white transition-colors cursor-pointer border-0"
              ) do
                render UI::Icon.new(:paper_plane, class: "w-3.5 h-3.5")
                plain "Issue"
              end
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
        div(class: "absolute top-5 left-5 z-20 w-[340px] flex flex-col " \
                   "bg-white border border-gray-200/70 rounded-2xl overflow-hidden " \
                   "max-h-[calc(100%-40px)] inv-no-print " \
                   "shadow-[0_8px_32px_rgba(0,0,0,0.07),0_2px_8px_rgba(0,0,0,0.04)]") do
          # Fixed header — stays visible while scrolling
          div(class: "px-5 pt-[14px] pb-[10px] flex-shrink-0") do
            panel_header
          end
          div(class: "h-px bg-gray-100 flex-shrink-0 mx-3")

          # Scrollable body — min-h-0 prevents flex item from overflowing its container
          div(class: "flex-1 min-h-0 overflow-y-auto") do
            div(class: "px-5 pt-4 pb-5 flex flex-col gap-4") do
              customer_section
              panel_divider
              details_section
              panel_divider
              amounts_section

              if @inv["notes"].present? || @inv["terms"].present?
                panel_divider
                notes_section
              end
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
          detail_row("Issue date", fmt_inv_date(@inv["issue_date"]))
          detail_row("Due date",  fmt_inv_date(@inv["due_date"]))
          detail_row("Sent",      fmt_inv_datetime(@inv["sent_at"]))      if @inv["sent_at"].present?
          detail_row("Paid at",   fmt_inv_datetime(@inv["paid_at"]))      if @inv["paid_at"].present?
          detail_row("Voided at", fmt_inv_datetime(@inv["voided_at"]))    if @inv["voided_at"].present?
          detail_row("Created",   fmt_inv_datetime(@inv["inserted_at"]))
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

      # ── Share pill (above invoice document) ──────────────────────────────────

      def share_pill
        url = checkout_url
        return unless url.present? && @inv["state"] != "draft"

        num    = @inv["number"].presence || "Invoice"
        due    = @inv["amount_due"].to_i
        wa_msg = "#{num} — #{format_money(due)}: #{url}"

        div(class: "w-full max-w-[680px] flex items-center gap-0 mb-3 inv-no-print " \
                   "bg-white border border-gray-200/80 rounded-2xl overflow-hidden " \
                   "shadow-[0_4px_20px_rgba(0,0,0,0.06)]") do
          div(class: "flex items-center gap-2.5 flex-1 min-w-0 px-4 py-[9px]") do
            span(class: "text-[10px] font-bold uppercase tracking-[0.1em] text-gray-300 flex-shrink-0") do
              plain "Share"
            end
            span(class: "w-px h-3 bg-gray-200 flex-shrink-0")
            a(href: url, target: "_blank", rel: "noopener noreferrer",
              class: "font-mono text-[11px] text-[#3D47F5] hover:underline truncate") { plain url }
          end

          span(class: "w-px h-5 bg-gray-100 flex-shrink-0")

          button(
            type:  "button",
            id:    "copy-inv-url-btn",
            data:  { url: url },
            class: "flex items-center gap-[5px] px-3.5 py-[9px] text-[11.5px] font-medium " \
                   "text-gray-500 hover:bg-gray-50 hover:text-gray-800 transition-colors cursor-pointer border-0 bg-transparent"
          ) do
            render UI::Icon.new(:copy, class: "w-3.5 h-3.5")
            plain "Copy"
          end

          span(class: "w-px h-5 bg-gray-100 flex-shrink-0")

          a(href:   "https://wa.me/?text=#{CGI.escape(wa_msg)}",
            target: "_blank",
            rel:    "noopener noreferrer",
            class:  "flex items-center gap-[5px] px-3.5 py-[9px] text-[11.5px] font-medium " \
                    "text-gray-500 hover:bg-gray-50 hover:text-gray-800 transition-colors no-underline") do
            span(class: "text-[13px] leading-none") { plain "💬" }
            plain "WhatsApp"
          end
        end
      end

      def print_script
        script(nonce: content_security_policy_nonce) do
          raw safe(<<~JS)
            (function () {
              var btn = document.getElementById('inv-print-btn');
              if (!btn) return;
              btn.addEventListener('click', function () { window.print(); });
            })();
          JS
        end
      end

      def copy_script
        script(nonce: content_security_policy_nonce) do
          raw safe(<<~JS)
            (function () {
              var btn = document.getElementById('copy-inv-url-btn');
              if (!btn) return;
              var url = btn.dataset.url;
              if (!url) return;
              btn.addEventListener('click', function () {
                navigator.clipboard.writeText(url).then(function () {
                  btn.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" class="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="20 6 9 17 4 12"/></svg><span>Copied</span>';
                  btn.style.color = '#16a34a';
                  setTimeout(function () {
                    btn.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" class="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg><span>Copy</span>';
                    btn.style.color = '';
                  }, 2000);
                }).catch(function () {});
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
        div(class: "absolute top-5 right-0 bottom-0 overflow-y-auto inv-right-area",
            style: "left: 385px") do
          div(class: "min-h-full flex flex-col items-center justify-start pt-0 pb-10 px-6 inv-doc-inner") do
            share_pill
            div(class: "w-full max-w-[680px] bg-white rounded-2xl overflow-hidden inv-doc-card " \
                       "shadow-[0_8px_40px_rgba(0,0,0,0.10),0_2px_12px_rgba(0,0,0,0.06)]") do
              document_header
              billing_strip_section
              status_banner
              line_items_section
              totals_section
              notes_footer if @inv["notes"].present? || @inv["terms"].present?
              invoice_doc_footer
            end
          end
        end
      end

      # ── Invoice document ──────────────────────────────────────────────────────

      def document_header
        merchant_name = current_user.active_membership&.merchant_name.to_s.presence || "Your business"
        initials      = merchant_name.split.first(2).map { |w| w[0].upcase }.join

        div(class: "flex items-start justify-between px-10 pt-9 pb-6 gap-6") do
          # Left: "Invoice" title + number
          div do
            p(class: "text-[34px] font-black text-gray-900 leading-none tracking-tight") { plain "Invoice" }
            p(class: "text-[13px] text-gray-400 mt-1.5 font-mono") do
              plain "#" + (@inv["number"] || @inv["id"].to_s.first(12)).to_s
            end
            div(class: "mt-2") { state_badge(@inv["state"]) }
          end
          # Right: logo + merchant name
          div(class: "flex items-center gap-2.5 flex-shrink-0 mt-1") do
            if @logo_url.present?
              img(src: @logo_url, alt: "Logo",
                  class: "w-10 h-10 rounded-[9px] object-cover flex-shrink-0")
            else
              div(class: "w-10 h-10 rounded-[9px] bg-[#3D47F5] flex items-center justify-center flex-shrink-0") do
                span(class: "text-[11px] font-extrabold text-white tracking-tight") { plain initials }
              end
            end
            p(class: "text-[15px] font-bold text-gray-900 leading-tight") { plain merchant_name }
          end
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

      def billing_strip_section
        merchant_name = current_user.active_membership&.merchant_name.to_s.presence || "Your business"
        customer_ref  = @inv["customer_reference"].presence || "—"

        # ── Divider 1
        div(class: "h-px bg-gray-100 mx-10")

        # ── Bill to / dates
        div(class: "flex items-start justify-between px-10 py-5") do
          div do
            billing_label("Bill to")
            p(class: "text-[13.5px] font-semibold text-gray-900 mt-[5px]") { plain customer_ref }
          end
          div(class: "flex items-start gap-7") do
            div(class: "text-right") do
              billing_label("Issued Date")
              p(class: "text-[13.5px] font-semibold text-gray-900 mt-[5px]") { plain fmt_inv_date(@inv["issue_date"]) }
            end
            div(class: "text-right") do
              billing_label("Due Date")
              p(class: "text-[13.5px] font-semibold text-gray-900 mt-[5px]") { plain fmt_inv_date(@inv["due_date"]) }
            end
          end
        end

        # ── Divider 2
        div(class: "h-px bg-gray-100 mx-10")

        # ── From / To
        div(class: "flex items-start justify-between px-10 py-5") do
          div do
            billing_label("From")
            p(class: "text-[13px] font-semibold text-gray-900 mt-[5px] leading-snug") { plain merchant_name }
          end
          div(class: "text-right") do
            billing_label("To")
            p(class: "text-[13px] font-semibold text-gray-900 mt-[5px] leading-snug") { plain customer_ref }
          end
        end
      end

      def billing_label(text)
        p(class: "text-[9.5px] font-semibold uppercase tracking-[0.1em] text-gray-400") { plain text }
      end

      def invoice_doc_footer
        div(class: "border-t border-gray-100 px-10 py-4 flex items-center justify-between") do
          div do
            p(class: "text-[9.5px] font-bold uppercase tracking-[0.1em] text-gray-400 mb-[3px]") { plain "Payment method" }
            p(class: "text-[11px] text-gray-400") { plain "Payment powered by Yagye" }
          end
          p(class: "text-[10.5px] text-gray-300") { plain fmt_date(Time.now) }
        end
      end

      def document_divider
        div(class: "mx-10 border-t border-gray-100")
      end

      def line_items_section
        items    = Array(@inv["line_items"])
        currency = @inv["currency"] || "GHS"

        div(class: "overflow-x-auto mx-6") do
          table(class: "w-full") do
            thead do
              tr(style: "background:#f9fafb;border-bottom:1px solid #f1f5f9") do
                th(class: "text-left pl-5 pr-3 py-3 text-[10.5px] font-bold uppercase tracking-[0.1em] text-gray-400") { plain "Description" }
                th(class: "text-right px-3 py-3 text-[10.5px] font-bold uppercase tracking-[0.1em] text-gray-400")  { plain "Qty" }
                th(class: "text-right px-3 py-3 text-[10.5px] font-bold uppercase tracking-[0.1em] text-gray-400")  { plain "Unit price" }
                th(class: "text-right px-3 py-3 text-[10.5px] font-bold uppercase tracking-[0.1em] text-gray-400")  { plain "Tax" }
                th(class: "text-right pl-3 pr-5 py-3 text-[10.5px] font-bold uppercase tracking-[0.1em] text-gray-400") { plain "Amount" }
              end
            end
            tbody do
              items.each do |item|
                unit   = item["unit_amount"].to_i
                qty    = item["quantity"].to_f
                bps    = item["tax_rate_bps"].to_i
                amount = (unit * qty + unit * qty * bps / 10_000.0).round

                tr(class: "border-b border-gray-50 last:border-0") do
                  td(class: "pl-5 pr-3 py-3.5 text-[13px] font-medium text-gray-800") { plain item["description"] || "—" }
                  td(class: "px-3 py-3.5 text-right text-[12.5px] text-gray-500 tabular-nums") do
                    plain qty % 1 == 0 ? qty.to_i.to_s : "%.2f" % qty
                  end
                  td(class: "px-3 py-3.5 text-right text-[12.5px] text-gray-500 tabular-nums") do
                    plain format_money(unit, currency: currency)
                  end
                  td(class: "px-3 py-3.5 text-right text-[12.5px] text-gray-500 tabular-nums") do
                    plain bps > 0 ? "#{(bps / 100.0).to_s.sub(/\.?0+$/, "")}%" : "—"
                  end
                  td(class: "pl-3 pr-5 py-3.5 text-right text-[13px] font-semibold text-gray-900 tabular-nums") do
                    plain format_money(amount, currency: currency)
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

        div(class: "h-px bg-gray-100 mx-6")
        div(class: "flex justify-end px-10 py-6") do
          div(class: "w-[280px] flex flex-col gap-[2px]") do
            totals_row("Subtotal", format_money(subtotal))                              if subtotal != total || tax > 0 || discount > 0
            totals_row("Tax",      format_money(tax))                                   if tax > 0
            totals_row("Discount", "− #{format_money(discount)}")                      if discount > 0
            totals_row("Paid",     "− #{format_money(paid)}", color: "text-green-600") if paid > 0
            div(class: "h-px bg-gray-200 my-2")
            # Bold "Total Amount" row
            div(class: "flex items-center justify-between py-[3px]") do
              p(class: "text-[13.5px] font-bold text-gray-900") { plain "Total Amount" }
              p(class: "text-[14px] font-bold text-gray-900 tabular-nums") { plain format_money(total) }
            end
            # Amount due (subtle subtitle; only meaningful when partially paid)
            div(class: "flex items-center justify-between pt-[2px]") do
              p(class: "text-[11px] text-gray-400") { plain "Amount due" }
              p(class: "text-[12px] font-semibold text-[#3D47F5] tabular-nums") { plain format_money(amount_due) }
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
        div(class: "px-10 pb-7 flex flex-col gap-5") do
          if @inv["notes"].present?
            div(class: "border border-gray-200 rounded-xl px-5 py-4") do
              p(class: "text-[12.5px] text-gray-600 leading-relaxed") { plain @inv["notes"] }
            end
          end
          if @inv["terms"].present?
            div do
              p(class: "text-[9.5px] font-bold uppercase tracking-[0.12em] text-gray-400 mb-1.5") { plain "Terms & conditions" }
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
        super(minor_units, currency: currency)
      end

      def checkout_url
        @inv["invoice_view_url"] || @inv["payment_link_checkout_url"]
      end

      def fmt_inv_date(val)
        return "—" unless val.present?
        (Date.parse(val) rescue val).then { |d| d.respond_to?(:strftime) ? d.strftime("%d %b %Y") : d }
      end

      def fmt_inv_datetime(val)
        return "—" unless val.present?
        (Time.parse(val) rescue val).then { |t| t.respond_to?(:strftime) ? t.strftime("%d %b %Y at %H:%M UTC") : t }
      end
    end
  end
end
