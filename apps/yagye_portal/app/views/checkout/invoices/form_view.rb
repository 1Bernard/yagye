# frozen_string_literal: true

module Checkout
  module Invoices
    class FormView < ApplicationComponent
      include UI::Theme

      CURRENCIES = %w[GHS NGN KES XOF].freeze

      def initialize(errors: [])
        @errors = errors
      end

      def view_template
        render Layout::Shell.new(
          active_nav: :invoices,
          title:      "New invoice",
          breadcrumbs: [
            { label: "Invoices", url: invoices_path },
            { label: "New invoice" }
          ]
        ) do
          render UI::PageHeader.new(
            title:    "New invoice",
            subtitle: "Create an invoice with line items for your customer."
          )

          render UI::ErrorSummary.new(errors: @errors) if @errors.any?

          form(action: invoices_path, method: "post", id: "invoice-form") do
            input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)

            render UI::Grid.new(columns: :sidebar) do
              left_column
              right_column
            end
          end
        end
      end

      private

      def left_column
        div(class: "flex flex-col gap-5") do
          customer_card
          line_items_card
          notes_card
        end
      end

      def right_column
        div(class: "flex flex-col gap-5") do
          invoice_details_card
          submit_card
        end
      end

      def customer_card
        render UI::Card.new do |c|
          c.header("Customer")
          c.body do
            div(class: "flex flex-col gap-4") do
              field("Customer reference", :customer_reference,
                    placeholder: "e.g. CUST-001 or email address",
                    hint: "Your own identifier for this customer (e.g. their email or internal ID).")
            end
          end
        end
      end

      def line_items_card
        render UI::Card.new do |c|
          c.header("Line items")
          c.body(padding: false) do
            div(data: { controller: "invoice-line-items" }) do
              div(class: "px-6 py-3 border-b border-gray-100 hidden",
                  data: { invoice_line_items_target: "header" }) do
                div(class: "grid grid-cols-[1fr_80px_120px_80px_24px] gap-3") do
                  p(class: TYPE_CAPTION) { plain "Description" }
                  p(class: "#{TYPE_CAPTION} text-right") { plain "Qty" }
                  p(class: "#{TYPE_CAPTION} text-right") { plain "Unit price" }
                  p(class: "#{TYPE_CAPTION} text-right") { plain "Tax %" }
                  span
                end
              end
              div(data: { invoice_line_items_target: "rows" }) { line_item_row(0) }

              div(class: "px-6 py-4 border-t border-gray-50") do
                button(type: "button",
                       class: "inline-flex items-center gap-2 text-[12.5px] text-[#3D47F5] font-medium " \
                              "hover:text-[#3340e0] transition-colors",
                       data: { action: "click->invoice-line-items#addItem" }) do
                  render UI::Icon.new(:plus, class: "w-3.5 h-3.5")
                  plain "Add line item"
                end
              end
            end
          end
        end
      end

      def line_item_row(index, description: "", quantity: 1, unit_amount: "", tax_rate: 0)
        div(class: "line-item-row px-6 py-3 border-b border-gray-50 last:border-0") do
          div(class: "grid grid-cols-[1fr_80px_120px_80px_24px] gap-3 items-start") do
            input(type: "text", name: "line_items[#{index}][description]", value: description,
                  placeholder: "Description",
                  class: "w-full h-8 border border-gray-200 rounded-[9px] px-3 text-[12.5px] " \
                         "text-gray-700 bg-white outline-none focus:border-[#3D47F5]")
            input(type: "number", name: "line_items[#{index}][quantity]", value: quantity,
                  min: "0.01", step: "0.01", placeholder: "1",
                  class: "w-full h-8 border border-gray-200 rounded-[9px] px-3 text-[12.5px] " \
                         "text-gray-700 bg-white outline-none focus:border-[#3D47F5] tabular-nums text-right")
            input(type: "number", name: "line_items[#{index}][unit_amount]", value: unit_amount,
                  min: "0", step: "0.01", placeholder: "0.00",
                  class: "w-full h-8 border border-gray-200 rounded-[9px] px-3 text-[12.5px] " \
                         "text-gray-700 bg-white outline-none focus:border-[#3D47F5] tabular-nums text-right")
            input(type: "number", name: "line_items[#{index}][tax_rate_bps]", value: tax_rate,
                  min: "0", max: "10000", step: "0.01", placeholder: "0",
                  title: "Tax rate in % (e.g. 15 for 15%)",
                  class: "w-full h-8 border border-gray-200 rounded-[9px] px-3 text-[12.5px] " \
                         "text-gray-700 bg-white outline-none focus:border-[#3D47F5] tabular-nums text-right",
                  data: { convert_bps: "true" })
            button(type: "button",
                   class: "h-8 flex items-center justify-center text-gray-300 hover:text-red-400 transition-colors",
                   data: { action: "click->invoice-line-items#removeItem" }) do
              render UI::Icon.new(:x, class: "w-4 h-4")
            end
          end
        end
      end

      def notes_card
        render UI::Card.new do |c|
          c.header("Notes & terms")
          c.body do
            div(class: "flex flex-col gap-4") do
              div do
                label(class: "#{TYPE_CAPTION} block mb-1") { plain "Notes" }
                textarea(name: "notes", rows: 3,
                         placeholder: "e.g. Thank you for your business.",
                         class: "w-full border border-gray-200 rounded-[9px] px-3 py-2 text-[12.5px] " \
                                "text-gray-700 bg-white outline-none focus:border-[#3D47F5] resize-none")
              end
              div do
                label(class: "#{TYPE_CAPTION} block mb-1") { plain "Terms" }
                textarea(name: "terms", rows: 2,
                         placeholder: "e.g. Payment due within 30 days.",
                         class: "w-full border border-gray-200 rounded-[9px] px-3 py-2 text-[12.5px] " \
                                "text-gray-700 bg-white outline-none focus:border-[#3D47F5] resize-none")
              end
            end
          end
        end
      end

      def invoice_details_card
        render UI::Card.new do |c|
          c.header("Invoice details")
          c.body do
            div(class: "flex flex-col gap-4") do
              field("Invoice number", :number, placeholder: "e.g. INV-00001",
                    hint: "Must be unique. Sequential numbers are a legal requirement in most jurisdictions.")

              div do
                label(class: "#{TYPE_CAPTION} block mb-1") { plain "Currency" }
                select(name: "currency",
                       class: "w-full h-8 border border-gray-200 rounded-[9px] px-3 text-[12.5px] " \
                              "text-gray-700 bg-white outline-none focus:border-[#3D47F5] appearance-none cursor-pointer") do
                  CURRENCIES.each do |c|
                    option(value: c, selected: c == "GHS") { plain c }
                  end
                end
              end

              div(class: "grid grid-cols-2 gap-3") do
                div do
                  label(class: "#{TYPE_CAPTION} block mb-1") { plain "Issue date" }
                  input(type: "date", name: "issue_date", value: Date.today.to_s,
                        class: "w-full h-8 border border-gray-200 rounded-[9px] px-3 text-[12.5px] " \
                               "text-gray-700 bg-white outline-none focus:border-[#3D47F5]")
                end
                div do
                  label(class: "#{TYPE_CAPTION} block mb-1") { plain "Due date" }
                  input(type: "date", name: "due_date", value: (Date.today + 30).to_s,
                        class: "w-full h-8 border border-gray-200 rounded-[9px] px-3 text-[12.5px] " \
                               "text-gray-700 bg-white outline-none focus:border-[#3D47F5]")
                end
              end
            end
          end
        end
      end

      def submit_card
        div(class: "bg-white border border-gray-100 rounded-2xl p-5") do
          button(type: "submit", form: "invoice-form", class: "#{BTN_PRIMARY} w-full justify-center") do
            plain "Create invoice"
          end
          p(class: "#{TYPE_CAPTION} text-center mt-2") { plain "Invoice will be saved as a draft." }
        end
      end

      def field(label_text, name, placeholder: "", hint: nil)
        div do
          label(class: "#{TYPE_CAPTION} block mb-1") { plain label_text }
          input(type: "text", name: name, placeholder: placeholder,
                class: "w-full h-8 border border-gray-200 rounded-[9px] px-3 text-[12.5px] " \
                       "text-gray-700 bg-white outline-none focus:border-[#3D47F5]")
          p(class: "#{TYPE_CAPTION} mt-1 text-gray-400") { plain hint } if hint
        end
      end
    end
  end
end
