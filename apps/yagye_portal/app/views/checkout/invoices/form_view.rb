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

      # ── Canvas dot grid ─────────────────────────────────────────────────────

      def canvas_styles
        style do
          raw safe(%(
            #invoice-canvas {
              background-color: #f8fafc;
              background-image: radial-gradient(circle, #d1d5db 1px, transparent 1px);
              background-size: 24px 24px;
            }
            .composer-row input:focus { box-shadow: none; }
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
          # Back
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
          # Panel title
          div(class: "flex items-center justify-between px-4 pt-[14px] pb-[10px] flex-shrink-0") do
            p(class: "text-[11px] font-bold uppercase tracking-[0.1em] text-gray-500") { plain "Invoice" }
          end

          div(class: "h-px bg-gray-100 flex-shrink-0 mx-3")

          # Scrollable body
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
        div(class: "h-px bg-gray-100 mx-3 flex-shrink-0")
      end

      def section_label(text)
        p(class: "text-[9px] font-bold uppercase tracking-[0.1em] text-gray-400 px-4 pt-3 pb-2 flex-shrink-0") do
          plain text
        end
      end

      # ── Bill to ──────────────────────────────────────────────────────────────

      def bill_to_section
        div(class: "px-4 pt-3 pb-4") do
          p(class: "text-[9px] font-bold uppercase tracking-[0.1em] text-gray-400 mb-2") { plain "Bill to" }
          input(
            type:        "text",
            name:        "customer_reference",
            placeholder: "Company name or contact email",
            class:       panel_input_cls,
            data:        { action: "input->invoice-compose#syncPreview" }
          )
          p(class: "text-[10.5px] text-gray-400 mt-[6px] leading-snug") do
            plain "Name or email your customer is known by. Used to find or create the customer record."
          end
        end
      end

      # ── Line items ────────────────────────────────────────────────────────────

      def line_items_section
        div(class: "px-4 pt-3 pb-4") do
          p(class: "text-[9px] font-bold uppercase tracking-[0.1em] text-gray-400 mb-3") { plain "Line items" }

          div(data: { invoice_compose_target: "rowList" }) do
            first_row
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

      def first_row
        div(class: "composer-row group", data: { invoice_compose_target: "composerRow" }) do
          div(class: "flex items-center gap-1.5 mb-[5px]") do
            input(
              type: "text", name: "line_items[0][description]", placeholder: "Description…",
              class: "#{panel_input_cls} flex-1 placeholder-gray-300",
              data: { action: "input->invoice-compose#syncPreview" }
            )
            # Remove button (hidden on last row via JS)
            button(
              type: "button",
              class: "w-[26px] h-[26px] flex-shrink-0 rounded-lg flex items-center justify-center " \
                     "text-gray-200 hover:text-red-400 hover:bg-red-50 transition-colors " \
                     "opacity-0 group-hover:opacity-100",
              data: { action: "click->invoice-compose#removeRow" }
            ) do
              render UI::Icon.new(:x, class: "w-3 h-3")
            end
          end
          div(class: "grid grid-cols-3 gap-[6px]") do
            row_subfield("Qty", :number, "line_items[0][quantity]", value: 1, min: "0.01", step: "0.01")
            row_subfield("Unit price", :number, "line_items[0][unit_amount]", placeholder: "0.00", min: "0", step: "0.01")
            row_subfield("Tax %", :number, "line_items[0][tax_rate_bps]", value: 0, min: "0", max: "10000",
                         step: "0.01", data: { convert_bps: "true" })
          end
        end
      end

      def row_subfield(label_text, type, name, **opts)
        label(class: "block") do
          span(class: "text-[9px] font-bold uppercase tracking-[0.1em] text-gray-400") { plain label_text }
          input(
            type:  type,
            name:  name,
            class: "#{panel_input_cls} tabular-nums text-right block w-full mt-[3px]",
            data:  { action: "input->invoice-compose#syncPreview" },
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
            )
            textarea(
              name:        "terms",
              rows:        2,
              placeholder: "e.g. Payment due within 30 days.",
              class:       panel_textarea_cls,
              data:        { action: "input->invoice-compose#syncPreview" }
            )
          end
        end
      end

      # ── Invoice details ───────────────────────────────────────────────────────

      def invoice_details_section
        div(class: "px-4 pt-3 pb-5") do
          p(class: "text-[9px] font-bold uppercase tracking-[0.1em] text-gray-400 mb-3") { plain "Invoice details" }
          div(class: "flex flex-col gap-2.5") do
            panel_field("Number", :text, "number",
                        placeholder: "INV-00001",
                        data: { action: "input->invoice-compose#syncPreview" })

            div do
              span(class: "text-[9px] font-bold uppercase tracking-[0.1em] text-gray-400 block mb-[5px]") do
                plain "Currency"
              end
              select(
                name:  "currency",
                class: "#{panel_input_cls} appearance-none cursor-pointer",
                data:  { action: "change->invoice-compose#syncPreview" }
              ) do
                CURRENCIES.each do |c|
                  option(value: c[:code], selected: c[:code] == "GHS") do
                    plain c[:label]
                  end
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

      def panel_field(label_text, type, name, **opts)
        div do
          span(class: "text-[9px] font-bold uppercase tracking-[0.1em] text-gray-400 block mb-[5px]") { plain label_text }
          input(type: type, name: name, class: panel_input_cls, **opts)
        end
      end

      # ── Preview area (right) ─────────────────────────────────────────────────

      def preview_area
        div(
          class: "absolute top-5 right-0 bottom-0 flex flex-col items-center " \
                 "justify-start pt-0 pb-8 overflow-y-auto",
          style: "left: 385px"
        ) do
          invoice_preview_card
        end
      end

      def invoice_preview_card
        div(
          class: "w-full max-w-[680px] bg-white rounded-2xl border border-gray-200/70 overflow-hidden " \
                 "shadow-[0_8px_32px_rgba(0,0,0,0.07),0_2px_8px_rgba(0,0,0,0.04)]"
        ) do
          preview_header
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
        div(class: "flex items-start justify-between px-10 pt-9 pb-7 border-b border-gray-100") do
          div do
            p(class: "text-[10px] font-bold tracking-[0.2em] uppercase text-[#3D47F5] mb-1") { plain "Invoice" }
            p(class: "text-[28px] font-bold text-gray-900 leading-none tabular-nums",
              data:  { invoice_compose_target: "pvNumber" }) { plain "—" }
          end
          div(class: "flex flex-col items-end gap-3") do
            span(class: "text-[11px] font-semibold px-3 py-1 rounded-full bg-amber-50 text-amber-600") do
              plain "Draft"
            end
            div(class: "grid grid-cols-2 gap-x-8 gap-y-0.5 text-right") do
              preview_date_cell("Issued", :pvIssued)
              preview_date_cell("Due",    :pvDue)
            end
          end
        end
      end

      def preview_date_cell(label, target)
        p(class: "text-[9.5px] font-bold uppercase tracking-[0.12em] text-gray-400") { plain label }
        p(class: "text-[12.5px] font-medium text-gray-800",
          data:  { invoice_compose_target: target }) do
          plain(target == :pvIssued ? Date.today.strftime("%d %b %Y") : (Date.today + 30).strftime("%d %b %Y"))
        end
      end

      # ── Preview: from / to ────────────────────────────────────────────────────

      def preview_from_to
        div(class: "grid grid-cols-2 gap-8 px-10 py-7") do
          div do
            p(class: "text-[9.5px] font-bold uppercase tracking-[0.12em] text-gray-400 mb-2") { plain "From" }
            p(class: "text-[13px] font-semibold text-gray-800 leading-snug") { plain "Your business" }
          end
          div do
            p(class: "text-[9.5px] font-bold uppercase tracking-[0.12em] text-gray-400 mb-2") { plain "Bill to" }
            p(class: "text-[13px] font-semibold text-gray-400 leading-snug",
              style: "font-style: italic",
              data:  { invoice_compose_target: "pvBillTo" }) { plain "Your customer" }
          end
        end
      end

      def preview_divider
        div(class: "mx-10 border-t border-dashed border-gray-200")
      end

      # ── Preview: line items table ─────────────────────────────────────────────

      def preview_line_items
        div(class: "overflow-x-auto") do
          table(class: "w-full") do
            thead do
              tr(class: "border-b border-gray-100") do
                th_cell("Description", "text-left px-8")
                th_cell("Qty",         "text-right px-3")
                th_cell("Unit price",  "text-right px-3")
                th_cell("Tax",         "text-right px-3")
                th_cell("Amount",      "text-right px-8")
              end
            end
            tbody(data: { invoice_compose_target: "pvRowsBody" }) do
              # Initial placeholder row
              tr(class: "border-b border-gray-50") do
                td(class: "px-8 py-3.5 text-[12.5px] text-gray-300 italic") { plain "Add a line item…" }
                td(class: "px-3 py-3.5")
                td(class: "px-3 py-3.5")
                td(class: "px-3 py-3.5")
                td(class: "px-8 py-3.5 text-right text-[12.5px] font-semibold text-gray-200 tabular-nums") { plain "GH₵ 0.00" }
              end
            end
          end
        end
      end

      def th_cell(text, extra_cls)
        th(class: "py-3 #{extra_cls} text-[9.5px] font-bold uppercase tracking-[0.1em] text-gray-400") { plain text }
      end

      # ── Preview: totals ───────────────────────────────────────────────────────

      def preview_totals
        div(class: "flex justify-end border-t border-gray-100 px-10 py-6") do
          div(class: "w-64 flex flex-col gap-[3px]") do
            totals_row("Subtotal", :pvSubtotal)
            tr_like_div("Tax", :pvTax, hidden: true, target: :pvTaxRow)
            totals_row("Total", :pvTotal, bold: true)
            div(class: "mt-3 flex items-center justify-between rounded-xl bg-[#3D47F5]/[0.06] px-4 py-3.5") do
              p(class: "text-[12px] font-bold text-[#3D47F5]") { plain "Amount due" }
              p(class: "text-[16px] font-bold text-[#3D47F5] tabular-nums",
                data: { invoice_compose_target: "pvAmountDue" }) { plain "GH₵ 0.00" }
            end
          end
        end
      end

      def totals_row(label, target_sym, bold: false)
        div(class: "flex items-center justify-between py-[2px]") do
          p(class: "text-[12px] #{bold ? 'font-semibold text-gray-800' : 'text-gray-400'}") { plain label }
          p(class: "text-[12.5px] #{bold ? 'font-semibold text-gray-900' : 'text-gray-500'} tabular-nums",
            data: { invoice_compose_target: target_sym }) { plain "GH₵ 0.00" }
        end
      end

      def tr_like_div(label, target_sym, hidden: false, target: nil)
        opts = hidden ? { hidden: true } : {}
        opts[:data] = { invoice_compose_target: target } if target
        div(class: "flex items-center justify-between py-[2px]", **opts) do
          p(class: "text-[12px] text-gray-400") { plain label }
          p(class: "text-[12.5px] text-gray-500 tabular-nums",
            data: { invoice_compose_target: target_sym }) { plain "GH₵ 0.00" }
        end
      end

      # ── Preview: notes / terms ────────────────────────────────────────────────

      def preview_notes_terms
        div(class: "border-t border-dashed border-gray-200 mx-10 mt-1")
        div(class: "px-10 py-7 grid grid-cols-2 gap-6") do
          div(hidden: true, data: { invoice_compose_target: "pvNotesSection" }) do
            p(class: "text-[9.5px] font-bold uppercase tracking-[0.12em] text-gray-400 mb-1.5") { plain "Notes" }
            p(class: "text-[12.5px] text-gray-600 leading-relaxed",
              data: { invoice_compose_target: "pvNotes" })
          end
          div(hidden: true, data: { invoice_compose_target: "pvTermsSection" }) do
            p(class: "text-[9.5px] font-bold uppercase tracking-[0.12em] text-gray-400 mb-1.5") { plain "Terms & conditions" }
            p(class: "text-[12.5px] text-gray-600 leading-relaxed",
              data: { invoice_compose_target: "pvTerms" })
          end
        end
      end

      # ── Preview: footer ───────────────────────────────────────────────────────

      def preview_footer
        div(class: "px-8 py-4 border-t border-gray-100 flex items-center justify-center gap-[5px]") do
          span(class: "flex w-[10px] h-[10px] text-gray-300") { render UI::Icon.new(:lock, class: "w-full h-full") }
          span(class: "text-[9.5px] text-gray-300") { plain "Secured by" }
          span(class: "text-[9.5px] font-bold text-[#3D47F5]") { plain "Yagye" }
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
