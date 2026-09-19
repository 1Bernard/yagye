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

      def initialize(errors: [], mode: "test")
        @errors = errors
        @mode   = mode
      end

      def view_template
        render Layout::Shell.new(
          active_nav: :invoices,
          title:      "New invoice",
          breadcrumbs: [
            { label: "Invoices", href: invoices_path },
            { label: "New invoice" }
          ],
          padded: false
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
              action: invoices_path,
              method: "post",
              class:  "absolute top-[76px] left-0 right-0 bottom-0"
            ) do
              input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
              editor_panel
              preview_area
            end
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
          a(href: invoices_path,
            class: "flex items-center justify-center w-8 h-8 rounded-xl " \
                   "hover:bg-gray-100 text-gray-400 hover:text-gray-700 transition-colors flex-shrink-0") do
            span(class: "flex w-[14px] h-[14px]") { render UI::Icon.new(:chev_left, class: "w-full h-full") }
          end

          div(class: "w-px h-5 bg-gray-200 flex-shrink-0")
          p(class: "text-[13.5px] font-semibold text-gray-900 px-1") { plain "New invoice" }

          span(class: "text-[10.5px] font-semibold px-[8px] py-[2px] rounded-full bg-gray-100 text-gray-500") do
            plain @mode.capitalize
          end

          div(class: "w-px h-5 bg-gray-200 flex-shrink-0")

          if @errors.any?
            span(class: "text-[10.5px] font-semibold px-[8px] py-[2px] rounded-full bg-red-50 text-red-600") do
              plain "#{@errors.size} error#{"s" if @errors.size > 1}"
            end
          end

          button(
            type:  "submit",
            form:  "invoice-form",
            class: "flex items-center gap-[5px] px-[10px] py-[5px] rounded-xl text-[12.5px] font-semibold " \
                   "bg-[#3D47F5] hover:bg-[#2e38d4] text-white transition-colors cursor-pointer border-0"
          ) { plain "Create invoice" }
        end
      end

      # ── Left editor panel ────────────────────────────────────────────────────

      def editor_panel
        div(
          class: "absolute top-5 left-5 bottom-5 z-20 w-[340px] flex flex-col " \
                 "bg-white border border-gray-200/70 rounded-2xl overflow-hidden " \
                 "shadow-[0_8px_32px_rgba(0,0,0,0.07),0_2px_8px_rgba(0,0,0,0.04)]"
        ) do
          div(class: "flex items-center px-4 pt-[14px] pb-[10px] flex-shrink-0") do
            p(class: "text-[11px] font-bold uppercase tracking-[0.1em] text-gray-500") { plain "Invoice" }
          end
          div(class: "h-px bg-gray-100 flex-shrink-0 mx-3")

          div(class: "flex-1 overflow-y-auto") do
            bill_to_section
            section_divider
            line_items_section
            section_divider
            notes_terms_section
            section_divider
            invoice_details_section
          end
        end
      end

      def section_divider
        div(class: "h-px bg-gray-100 mx-3")
      end

      # ── Bill to ──────────────────────────────────────────────────────────────

      def bill_to_section
        div(class: "px-4 pt-3 pb-4") do
          p(class: "text-[9px] font-bold uppercase tracking-[0.1em] text-gray-400 mb-2") { plain "Bill to" }
          input(
            type:        "text",
            name:        "customer_reference",
            value:       DEMO[:customer],
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
            DEMO[:rows].each_with_index do |row, i|
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
            ) { plain DEMO[:notes] }
            textarea(
              name:        "terms",
              rows:        2,
              placeholder: "e.g. Payment due within 30 days.",
              class:       panel_textarea_cls,
              data:        { action: "input->invoice-compose#syncPreview" }
            ) { plain DEMO[:terms] }
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
              input(type: "text", name: "number", value: DEMO[:number],
                    placeholder: "INV-00001", class: panel_input_cls,
                    data: { action: "input->invoice-compose#syncPreview" })
            end

            div do
              span(class: "text-[9px] font-bold uppercase tracking-[0.1em] text-gray-400 block mb-[5px]") { plain "Currency" }
              select(name: "currency", class: "#{panel_input_cls} appearance-none cursor-pointer",
                     data: { action: "change->invoice-compose#syncPreview" }) do
                CURRENCIES.each do |c|
                  option(value: c[:code], selected: c[:code] == DEMO[:currency]) { plain c[:label] }
                end
              end
            end

            div(class: "grid grid-cols-2 gap-2") do
              div do
                span(class: "text-[9px] font-bold uppercase tracking-[0.1em] text-gray-400 block mb-[5px]") { plain "Issue date" }
                input(type: "date", name: "issue_date", value: Date.today.to_s,
                      class: panel_input_cls, data: { action: "change->invoice-compose#syncPreview" })
              end
              div do
                span(class: "text-[9px] font-bold uppercase tracking-[0.1em] text-gray-400 block mb-[5px]") { plain "Due date" }
                input(type: "date", name: "due_date", value: (Date.today + 30).to_s,
                      class: panel_input_cls, data: { action: "change->invoice-compose#syncPreview" })
              end
            end
          end
        end
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
          preview_meta_strip
          preview_from_to
          preview_divider
          preview_line_items
          preview_totals
          preview_notes_terms
          preview_footer
        end
      end

      # ── Preview: header ────────────────────────────────────────────────────────

      def preview_header
        div(class: "flex items-start justify-between px-10 pt-8 pb-6") do
          # Business identity (left)
          div(class: "flex items-center gap-3") do
            div(
              class: "w-11 h-11 rounded-[10px] bg-[#3D47F5] flex items-center justify-center flex-shrink-0 " \
                     "shadow-[0_2px_8px_rgba(61,71,245,0.35)]"
            ) do
              span(class: "text-[12px] font-bold text-white tracking-tight") { plain "YB" }
            end
            div do
              p(class: "text-[14px] font-bold text-gray-900 leading-tight") { plain "Your business" }
              p(class: "text-[11px] text-gray-400 mt-[1px]") { plain "hello@yourbusiness.com" }
            end
          end

          # Invoice identity (right)
          div(class: "flex flex-col items-end gap-2") do
            div(class: "flex items-center gap-2") do
              span(class: "text-[10px] font-bold tracking-[0.25em] uppercase text-[#3D47F5]") { plain "Invoice" }
              span(class: "text-[10.5px] font-semibold px-2.5 py-[3px] rounded-full bg-amber-50 text-amber-600 border border-amber-200/70") do
                plain "Draft"
              end
            end
            p(class: "text-[30px] font-extrabold text-gray-900 leading-none tabular-nums tracking-tight",
              data: { invoice_compose_target: "pvNumber" }) { plain DEMO[:number] }
          end
        end
      end

      # ── Preview: dates strip ──────────────────────────────────────────────────

      def preview_meta_strip
        div(class: "mx-10 mb-6 flex items-center gap-8 px-4 py-3 rounded-xl bg-gray-50 border border-gray-100") do
          div(class: "flex items-center gap-2") do
            p(class: "text-[9.5px] font-bold uppercase tracking-[0.12em] text-gray-400") { plain "Issued" }
            p(class: "text-[12.5px] font-semibold text-gray-700 tabular-nums",
              data: { invoice_compose_target: "pvIssued" }) { plain Date.today.strftime("%d %b %Y") }
          end
          div(class: "w-px h-4 bg-gray-200")
          div(class: "flex items-center gap-2") do
            p(class: "text-[9.5px] font-bold uppercase tracking-[0.12em] text-gray-400") { plain "Due" }
            p(class: "text-[12.5px] font-semibold text-gray-700 tabular-nums",
              data: { invoice_compose_target: "pvDue" }) { plain (Date.today + 30).strftime("%d %b %Y") }
          end
        end
      end

      # ── Preview: from / to ────────────────────────────────────────────────────

      def preview_from_to
        div(class: "grid grid-cols-2 gap-8 px-10 pb-6") do
          div do
            p(class: "text-[9.5px] font-bold uppercase tracking-[0.12em] text-gray-400 mb-2") { plain "From" }
            p(class: "text-[13px] font-semibold text-gray-800 leading-snug") { plain "Your business" }
            p(class: "text-[11.5px] text-gray-400 mt-[2px] leading-relaxed") { plain "Accra, Ghana" }
          end
          div do
            p(class: "text-[9.5px] font-bold uppercase tracking-[0.12em] text-gray-400 mb-2") { plain "Bill to" }
            p(class: "text-[13px] font-semibold text-gray-800 leading-snug",
              data: { invoice_compose_target: "pvBillTo" }) { plain DEMO[:customer] }
          end
        end
      end

      def preview_divider
        div(class: "mx-10 border-t border-dashed border-gray-200")
      end

      # ── Preview: line items table ─────────────────────────────────────────────

      def preview_line_items
        div(class: "overflow-x-auto mt-1") do
          table(class: "w-full") do
            thead do
              tr(class: "bg-gray-50/80 border-y border-gray-100") do
                th_cell("Description", "text-left pl-10 pr-4")
                th_cell("Qty",         "text-right px-3 w-14")
                th_cell("Unit price",  "text-right px-3 w-28")
                th_cell("Tax",         "text-right px-3 w-16")
                th_cell("Amount",      "text-right pl-3 pr-10 w-32")
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
                  "GH₵ #{sprintf('%.2f', amount / 100.0)}"
                )
              end
            end
          end
        end
      end

      def preview_static_row(desc, qty, unit, tax, amount)
        tr(class: "border-b border-gray-50 last:border-0") do
          td(class: "pl-10 pr-4 py-3.5 text-[12.5px] text-gray-800") { plain desc }
          td(class: "px-3 py-3.5 text-right text-[12px] text-gray-400 tabular-nums") { plain qty }
          td(class: "px-3 py-3.5 text-right text-[12px] text-gray-400 tabular-nums") { plain unit }
          td(class: "px-3 py-3.5 text-right text-[12px] text-gray-400 tabular-nums") { plain tax }
          td(class: "pl-3 pr-10 py-3.5 text-right text-[12.5px] font-semibold text-gray-900 tabular-nums") { plain amount }
        end
      end

      def th_cell(text, extra_cls)
        th(class: "py-2.5 #{extra_cls} text-[9px] font-bold uppercase tracking-[0.1em] text-gray-400") { plain text }
      end

      # ── Preview: totals ───────────────────────────────────────────────────────

      def preview_totals
        demo_subtotal = DEMO[:rows].sum { |r| (r[:unit] * 100 * r[:qty]).round }

        div(class: "flex justify-end border-t border-gray-100 px-10 py-6") do
          div(class: "w-[260px] flex flex-col") do
            totals_row("Subtotal", :pvSubtotal,
                       default: "GH₵ #{sprintf('%.2f', demo_subtotal / 100.0)}")
            div(class: "flex items-center justify-between py-[2px]",
                hidden: true, data: { invoice_compose_target: "pvTaxRow" }) do
              p(class: "text-[12px] text-gray-400") { plain "Tax" }
              p(class: "text-[12.5px] text-gray-500 tabular-nums",
                data: { invoice_compose_target: "pvTax" }) { plain "GH₵ 0.00" }
            end
            div(class: "h-px bg-gray-100 my-2")
            totals_row("Total", :pvTotal, bold: true,
                       default: "GH₵ #{sprintf('%.2f', demo_subtotal / 100.0)}")

            # Amount due
            div(class: "mt-3 flex items-center justify-between " \
                        "rounded-xl bg-gray-50 border border-gray-100 px-4 py-3.5") do
              p(class: "text-[12px] font-bold text-gray-700") { plain "Amount due" }
              p(class: "text-[17px] font-extrabold text-gray-900 tabular-nums tracking-tight",
                data: { invoice_compose_target: "pvAmountDue" }) do
                plain "GH₵ #{sprintf('%.2f', demo_subtotal / 100.0)}"
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
          class: "border-t border-dashed border-gray-200 mx-10"
        )
        div(
          class: "px-10 py-6 grid grid-cols-2 gap-6",
          data:  { invoice_compose_target: "pvNotesTermsSection" }
        ) do
          div(data: { invoice_compose_target: "pvNotesSection" }) do
            p(class: "text-[9.5px] font-bold uppercase tracking-[0.12em] text-gray-400 mb-1.5") { plain "Notes" }
            p(class: "text-[12.5px] text-gray-600 leading-relaxed",
              data: { invoice_compose_target: "pvNotes" }) { plain DEMO[:notes] }
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
        div(class: "mx-10 border-t border-gray-100")
        div(class: "px-10 py-5 flex items-center justify-between") do
          p(class: "text-[10px] text-gray-300") { plain "yagye.com" }
          div(class: "flex items-center gap-[5px]") do
            span(class: "text-[10px] text-gray-300") { plain "Payment powered by" }
            span(class: "text-[10px] font-bold text-[#3D47F5]/60") { plain "Yagye" }
          end
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
