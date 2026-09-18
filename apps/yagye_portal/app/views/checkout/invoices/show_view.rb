# frozen_string_literal: true

module Checkout
  module Invoices
    class ShowView < ApplicationComponent
      include UI::Theme

      STATE_COLORS = {
        "draft"          => "bg-gray-100 text-gray-600",
        "open"           => "bg-blue-50 text-blue-700",
        "partially_paid" => "bg-amber-50 text-amber-700",
        "paid"           => "bg-green-50 text-green-700",
        "overdue"        => "bg-red-50 text-red-700",
        "void"           => "bg-gray-100 text-gray-400",
        "uncollectible"  => "bg-gray-100 text-gray-400"
      }.freeze

      def initialize(invoice:)
        @inv = invoice
      end

      def view_template
        render Layout::Shell.new(
          active_nav: :invoices,
          title:      @inv["number"] || @inv["id"],
          breadcrumbs: [
            { label: "Invoices", url: invoices_path },
            { label: @inv["number"] || @inv["id"].to_s.first(16) }
          ]
        ) do
          render UI::Grid.new(columns: :sidebar) do
            left_column
            right_column
          end
        end
      end

      private

      def left_column
        div(class: "flex flex-col gap-5") do
          invoice_document
        end
      end

      def right_column
        div(class: "flex flex-col gap-5") do
          actions_card
          payment_link_card if @inv["payment_link_id"].present?
          details_card
        end
      end

      # ── Invoice document ─────────────────────────────────────────────────────
      # Designed to read like a real printed invoice, not a data card.

      def invoice_document
        div(class: "bg-white border border-gray-100 rounded-2xl overflow-hidden") do
          document_header
          status_banner
          from_to_section
          document_divider
          line_items_section
          totals_section
          notes_footer if @inv["notes"].present? || @inv["terms"].present?
        end
      end

      def document_header
        div(class: "flex items-start justify-between px-10 pt-9 pb-7 " \
                   "border-b border-gray-100") do
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
              doc_date_cell("Issued",  @inv["issue_date"])
              doc_date_cell("Due",     @inv["due_date"])
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
              when "overdue"
                { bg: "bg-red-50 border-red-100",   text: "text-red-700",   msg: "This invoice is overdue." }
              when "paid"
                { bg: "bg-green-50 border-green-100", text: "text-green-700", msg: "Payment received in full." }
              when "void"
                { bg: "bg-gray-50 border-gray-200",  text: "text-gray-500",  msg: "This invoice has been voided." }
              end

        div(class: "px-10 py-3 border-b #{cfg[:bg]} #{cfg[:text]} text-[12px] font-medium") do
          plain cfg[:msg]
        end
      end

      def from_to_section
        div(class: "grid grid-cols-2 gap-8 px-10 py-7") do
          div do
            p(class: "text-[10.5px] font-bold uppercase tracking-[0.12em] text-gray-400 mb-2") { plain "From" }
            p(class: "text-[13px] font-semibold text-gray-800 leading-snug") { plain "Yagye Payments" }
            p(class: "text-[12px] text-gray-400 mt-0.5") { plain @inv["merchant_code"] || "—" }
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
                th(class: "text-right px-4 py-3  text-[10.5px] font-bold uppercase tracking-[0.1em] text-gray-400") { plain "Qty" }
                th(class: "text-right px-4 py-3  text-[10.5px] font-bold uppercase tracking-[0.1em] text-gray-400") { plain "Unit price" }
                th(class: "text-right px-4 py-3  text-[10.5px] font-bold uppercase tracking-[0.1em] text-gray-400") { plain "Tax" }
                th(class: "text-right px-10 py-3 text-[10.5px] font-bold uppercase tracking-[0.1em] text-gray-400") { plain "Amount" }
              end
            end
            tbody do
              items.each_with_index do |item, idx|
                unit   = item["unit_amount"].to_i
                qty    = item["quantity"].to_f
                bps    = item["tax_rate_bps"].to_i
                amount = (unit * qty + unit * qty * bps / 10_000.0).round
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
            totals_row("Tax",      format_money(tax))              if tax > 0
            totals_row("Discount", "− #{format_money(discount)}")  if discount > 0
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
        div(class: "px-10 py-7 grid gap-4 #{@inv['notes'].present? && @inv['terms'].present? ? 'grid-cols-2' : 'grid-cols-1'}") do
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

      # ── Actions ──────────────────────────────────────────────────────────────

      def actions_card
        state = @inv["state"]
        return unless %w[draft open partially_paid overdue].include?(state)

        render UI::Card.new do |c|
          c.header("Actions")
          c.body do
            div(class: "flex flex-col gap-2") do
              if state == "draft"
                form(action: issue_invoice_path(@inv["id"]), method: "post") do
                  input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
                  button(type: "submit",
                         class: "w-full flex items-center justify-center gap-2 h-9 px-4 " \
                                "bg-[#3D47F5] text-white rounded-[9px] text-[12.5px] font-medium " \
                                "hover:bg-[#3340e0] transition-colors") do
                    render UI::Icon.new(:send, class: "w-3.5 h-3.5")
                    plain "Issue invoice"
                  end
                end
              end
              if %w[open partially_paid overdue].include?(state)
                form(action: void_invoice_path(@inv["id"]), method: "post") do
                  input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
                  button(type: "submit",
                         class: "w-full flex items-center justify-center gap-2 h-9 px-4 " \
                                "border border-red-200 text-red-600 rounded-[9px] text-[12.5px] font-medium " \
                                "hover:bg-red-50 transition-colors",
                         data: { confirm: "Void this invoice? This cannot be undone." }) do
                    render UI::Icon.new(:x, class: "w-3.5 h-3.5")
                    plain "Void invoice"
                  end
                end
              end
            end
          end
        end
      end

      # ── Payment link ──────────────────────────────────────────────────────────

      def payment_link_card
        render UI::Card.new do |c|
          c.header("Collected via")
          c.body do
            div(class: "flex items-center gap-3") do
              div(class: "w-8 h-8 rounded-xl bg-gray-50 flex items-center justify-center flex-shrink-0") do
                span(class: "flex w-4 h-4 text-gray-500") { render UI::Icon.new(:link, class: "w-full h-full") }
              end
              div do
                p(class: TYPE_BODY_MD) { plain "Payment link" }
                p(class: TYPE_MONO) { plain @inv["payment_link_id"] }
              end
            end
          end
        end
      end

      # ── Details ──────────────────────────────────────────────────────────────

      def details_card
        render UI::Card.new do |c|
          c.header("Invoice details")
          c.body(padding: false) do
            render UI::DetailList.new do |list|
              list.row("Invoice ID",  @inv["id"], mono: true)
              list.row("Number",      @inv["number"] || "—")
              list.row("Mode",        @inv["mode"]&.capitalize || "—")
              list.row("Currency",    @inv["currency"] || "—")
              list.row("State")       { state_badge(@inv["state"]) }
              list.row("Amount paid", format_money(@inv["amount_paid"].to_i))
              list.row("Issued")      { plain @inv["sent_at"] ? Time.parse(@inv["sent_at"]).strftime("%d %b %Y at %H:%M") : "Not yet issued" }
              list.row("Paid at")     { plain @inv["paid_at"] ? Time.parse(@inv["paid_at"]).strftime("%d %b %Y at %H:%M") : "—" }
              list.row("Voided at")   { plain @inv["voided_at"] ? Time.parse(@inv["voided_at"]).strftime("%d %b %Y at %H:%M") : "—" }
              list.row("Created",     @inv["inserted_at"] ? Time.parse(@inv["inserted_at"]).strftime("%d %b %Y at %H:%M") : "—")
            end
          end
        end
      end

      # ── Helpers ──────────────────────────────────────────────────────────────

      def state_badge(state)
        cls = STATE_COLORS[state] || "bg-gray-100 text-gray-500"
        span(class: "inline-flex items-center px-2.5 py-1 rounded-full text-[11.5px] font-semibold #{cls}") do
          plain (state || "—").tr("_", " ").capitalize
        end
      end

      def format_money(minor_units, currency: @inv["currency"] || "GHS")
        "#{currency} #{"%.2f" % (minor_units / 100.0)}"
      end
    end
  end
end
