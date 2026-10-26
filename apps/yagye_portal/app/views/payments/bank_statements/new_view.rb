# frozen_string_literal: true

module Payments
  module BankStatements
    class NewView < ApplicationComponent
      include UI::Theme

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

                  div(class: "flex flex-col gap-5") do
                    div(class: "grid grid-cols-2 gap-4") do
                      field("Account reference", :account_reference,
                            placeholder: "e.g. YAGYE-GCB-001", required: true)

                      field("Statement date", :statement_date,
                            type: "date", required: true)
                    end

                    div(class: "grid grid-cols-2 gap-4") do
                      div do
                        p(class: "#{TEXT_LABEL} mb-1.5") { plain "Currency" }
                        select(name: "currency", class: SELECT_FIELD) do
                          option(value: "GHS", selected: "selected") { plain "GHS — Ghana Cedi" }
                          option(value: "USD") { plain "USD — US Dollar" }
                          option(value: "EUR") { plain "EUR — Euro" }
                        end
                      end

                      div do
                        p(class: "#{TEXT_LABEL} mb-1.5") { plain "Mode" }
                        select(name: "mode", class: SELECT_FIELD) do
                          option(value: "live", selected: "selected") { plain "Live" }
                          option(value: "simulation") { plain "Simulation" }
                        end
                      end
                    end

                    div(class: "grid grid-cols-2 gap-4") do
                      ghs_field("Opening balance", :opening_balance,
                                placeholder: "0.00", required: true, value: "0")
                      ghs_field("Closing balance", :closing_balance,
                                placeholder: "e.g. 98000.00")
                    end

                    div do
                      p(class: "#{TEXT_LABEL} mb-1") { plain "CSV lines" }
                      p(class: "#{TYPE_CAPTION} mb-2") do
                        plain "One line per row: "
                        code(class: "#{TYPE_MONO} bg-gray-100 px-1 rounded text-[11px]") do
                          plain "value_date,narrative,amount"
                        end
                        plain " — amount in cedis, credits positive, debits negative."
                      end
                      textarea(
                        name:        "csv_lines",
                        rows:        "10",
                        placeholder: "2026-10-01,Opening balance credit,50000.00\n" \
                                     "2026-10-02,Settlement credit from MTN MoMo,8450.00\n" \
                                     "2026-10-03,Bank charges,-25.00",
                        required:    true,
                        class:       "#{INPUT_FIELD} font-mono !py-2.5 resize-y leading-relaxed"
                      )
                    end

                    div(class: "border-t border-gray-100 pt-4 flex items-center gap-3") do
                      render UI::Button.new(variant: :primary, type: "submit") do
                        render UI::Icon.new(:upload, class: ICON_SM)
                        plain "Import statement"
                      end
                      a(href: payments_bank_statements_path, class: BTN_GHOST) do
                        plain "Cancel"
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end

      private

      def field(label_text, name, type: "text", placeholder: nil, required: false, value: nil)
        div do
          p(class: "#{TEXT_LABEL} mb-1.5") { plain label_text }
          input(
            type:        type,
            name:        name.to_s,
            value:       value,
            placeholder: placeholder,
            required:    required,
            class:       INPUT_FIELD
          )
        end
      end

      def ghs_field(label_text, name, placeholder: nil, required: false, value: nil)
        div do
          p(class: "#{TEXT_LABEL} mb-1.5") { plain label_text }
          div(class: "relative") do
            span(class: "absolute left-3.5 top-1/2 -translate-y-1/2 px-2 py-0.5 rounded " \
                        "bg-gray-100 #{TYPE_CAPTION} font-semibold pointer-events-none select-none") do
              plain "GHS"
            end
            input(
              type:        "number",
              name:        name.to_s,
              value:       value,
              step:        "0.01",
              min:         "0",
              placeholder: placeholder,
              required:    required,
              class:       "#{INPUT_FIELD} !pl-16 font-mono text-[13.5px] tabular-nums"
            )
          end
        end
      end
    end
  end
end
