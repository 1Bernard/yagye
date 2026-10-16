# frozen_string_literal: true

module Ops
  module BankStatements
    class NewView < ApplicationComponent
      include UI::Theme

      def view_template
        render Layout::Shell.new(
          active_nav:  :reconciliation,
          title:       "Import Statement",
          breadcrumbs: [
            { label: "Bank Statements", href: ops_bank_statements_path },
            { label: "Import" }
          ]
        ) do
          render UI::PageHeader.new(
            title:    "Import bank statement",
            subtitle: "Paste CSV lines from a bank export to import a statement for reconciliation."
          )

          div(class: "max-w-2xl") do
            render UI::Card.new do |c|
              c.header("Statement details")
              c.body do
                form(action: ops_bank_statements_path, method: "post") do
                  input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)

                  div(class: "flex flex-col gap-4") do
                    field("Account reference", :account_reference,
                          type: "text", placeholder: "e.g. YAGYE-GCB-001",
                          required: true)

                    field("Statement date", :statement_date,
                          type: "date", required: true)

                    div do
                      label(class: "block text-[12.5px] font-medium text-gray-700 mb-1.5") do
                        plain "CSV lines"
                      end
                      p(class: "#{TYPE_CAPTION} mb-2") do
                        plain "One line per row: date,description,amount,checksum (amount in cedis, e.g. 150.00)"
                      end
                      textarea(
                        name: "csv_lines",
                        rows: "12",
                        placeholder: "2026-10-01,Opening balance,5000.00,abc123\n2026-10-01,Payment settlement,-250.00,def456",
                        required: true,
                        class: "w-full border border-gray-200 rounded-[10px] px-3 py-2.5 " \
                               "text-[12.5px] text-gray-700 bg-white font-mono outline-none " \
                               "focus:ring-1 focus:ring-[#{BRAND}] resize-y leading-relaxed"
                      )
                    end

                    div(class: "pt-2 flex gap-3") do
                      render UI::Button.new(variant: :primary, type: "submit") { plain "Import statement" }
                      a(href: ops_bank_statements_path,
                        class: "#{BTN_SECONDARY} no-underline") { plain "Cancel" }
                    end
                  end
                end
              end
            end
          end
        end
      end

      private

      def field(label_text, name, type: "text", placeholder: nil, required: false)
        div do
          label(class: "block text-[12.5px] font-medium text-gray-700 mb-1.5") do
            plain label_text
          end
          input(
            type: type,
            name: name.to_s,
            placeholder: placeholder,
            required: required,
            class: "w-full border border-gray-200 rounded-[10px] px-3 py-2 text-[13px] " \
                   "text-gray-700 bg-white outline-none focus:ring-1 focus:ring-[#{BRAND}]"
          )
        end
      end
    end
  end
end
