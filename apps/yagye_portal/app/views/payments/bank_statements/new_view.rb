# frozen_string_literal: true

module Payments
  module BankStatements
    class NewView < ApplicationComponent
      include UI::Theme
      include Phlex::Rails::Helpers::LabelTag

      def view_template
        render Layout::Shell.new(
          active_nav:  :bank_statements,
          title:       "Import Statement",
          breadcrumbs: [
            { label: "Bank Statements", href: payments_bank_statements_path },
            { label: "Import" }
          ]
        ) do
          render UI::PageHeader.new(
            title:    "Import bank statement",
            subtitle: "Paste CSV lines from a bank export to create a reconciliation record."
          )

          div(class: "max-w-2xl") do
            render UI::Card.new do |c|
              c.header("Statement details")
              c.body do
                form(action: payments_bank_statements_path, method: "post") do
                  input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
                  input(type: "hidden", name: "source", value: "csv_upload")

                  div(class: "flex flex-col gap-4") do
                    div(class: "grid grid-cols-2 gap-4") do
                      field("Account reference", :account_reference,
                            placeholder: "e.g. YAGYE-GCB-001", required: true)

                      field("Statement date", :statement_date,
                            type: "date", required: true)
                    end

                    div(class: "grid grid-cols-3 gap-4") do
                      div do
                        label_tag("Currency")
                        select(name: "currency", class: SELECT_FIELD) do
                          option(value: "GHS", selected: "selected") { plain "GHS — Ghana Cedi" }
                          option(value: "USD") { plain "USD — US Dollar" }
                          option(value: "EUR") { plain "EUR — Euro" }
                        end
                      end

                      div do
                        label(class: "block text-[12.5px] font-medium text-gray-700 mb-1.5") { plain "Mode" }
                        select(name: "mode", class: SELECT_FIELD) do
                          option(value: "live", selected: "selected") { plain "Live" }
                          option(value: "simulation") { plain "Simulation" }
                        end
                      end

                      div do
                        label(class: "block text-[12.5px] font-medium text-gray-700 mb-1.5") { plain "Opening balance" }
                        div(class: "relative") do
                          span(class: "absolute left-3 top-1/2 -translate-y-1/2 text-[11px] text-gray-400") { plain "GHS" }
                          input(type: "number", name: "opening_balance", value: "0",
                                step: "0.01", min: "0", required: true,
                                class: "#{INPUT_FIELD} pl-10")
                        end
                      end
                    end

                    field("Closing balance (GHS)", :closing_balance,
                          type: "number", placeholder: "e.g. 98000.00")

                    div do
                      label(class: "block text-[12.5px] font-medium text-gray-700 mb-1") do
                        plain "CSV lines"
                      end
                      p(class: "#{TYPE_CAPTION} mb-2") do
                        plain "One line per row: "
                        code(class: "#{TYPE_MONO} bg-gray-100 px-1 rounded text-[11px]") do
                          plain "value_date,narrative,amount"
                        end
                        plain " — amount in cedis, credits positive, debits negative."
                      end
                      textarea(
                        name: "csv_lines",
                        rows: "12",
                        placeholder: "2026-10-01,Opening balance credit,50000.00\n2026-10-02,Settlement credit from MTN MoMo,8450.00\n2026-10-03,Bank charges,-25.00",
                        required: true,
                        class: "w-full border border-gray-200 rounded-[10px] px-3 py-2.5 " \
                               "text-[12.5px] text-gray-700 bg-white font-mono outline-none " \
                               "focus:ring-1 focus:ring-[#{BRAND}] resize-y leading-relaxed"
                      )
                    end

                    div(class: "pt-1 flex gap-3") do
                      render UI::Button.new(variant: :primary, type: "submit") do
                        render UI::Icon.new(:upload, class: ICON_SM)
                        plain " Import statement"
                      end
                      a(href: payments_bank_statements_path,
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
            class: INPUT_FIELD
          )
        end
      end
    end
  end
end
