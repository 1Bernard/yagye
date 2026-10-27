# frozen_string_literal: true

module Payments
  module BankStatements
    class UploadModalView < ApplicationComponent
      include UI::Theme

      def view_template
        turbo_frame(id: "modal-frame") do
          div(class: MODAL_HEAD) do
            h2(class: TEXT_H2) { plain "Import bank statement" }
            button(type: "button", class: XBTN, data: { action: "click->modal#close" }) do
              render UI::Icon.new(:x, class: ICON_SM)
            end
          end

          form(action: payments_bank_statements_path,
               method: "post",
               enctype: "multipart/form-data",
               data: { controller: "bank-statement-upload", turbo_frame: "_top" }) do
            input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
            input(type: "hidden", name: "source",   value: "csv_upload")
            input(type: "hidden", name: "currency", value: "GHS")
            input(type: "hidden", name: "mode",     value: "live")

            div(class: MODAL_BODY) do
              p(class: "#{TYPE_CAPTION} mb-5") do
                plain "Upload the CSV export from your bank. Each row must contain: " \
                      "value date, narrative, amount (credits positive, debits negative)."
              end

              div(class: "flex flex-col gap-4") do
                # ── Account reference ──────────────────────────────────────────
                div do
                  p(class: "#{TEXT_LABEL} mb-1.5") { plain "Account reference" }
                  input(type: "text", name: "account_reference",
                        placeholder: "e.g. YAGYE-GCB-001",
                        required: true, class: INPUT_FIELD)
                  p(class: "#{TYPE_CAPTION} mt-1") do
                    plain "Use a consistent reference for each of Yagye's bank accounts."
                  end
                end

                # ── File drop zone ─────────────────────────────────────────────
                label(class: "flex flex-col items-center justify-center gap-2 px-4 py-8 " \
                             "border-2 border-dashed border-gray-200 rounded-xl bg-gray-50 " \
                             "hover:border-gray-300 hover:bg-gray-100 transition-colors cursor-pointer",
                      data: { action: "click->bank-statement-upload#openFilePicker" }) do
                  span(class: "w-8 h-8 text-gray-400") do
                    render UI::Icon.new(:upload, class: "w-full h-full")
                  end
                  p(class: "text-[13px] font-medium text-gray-700") { plain "Choose a CSV file" }
                  p(class: TYPE_CAPTION) { plain "value_date, narrative, amount" }
                  input(type: "file", name: "csv_file", accept: ".csv,text/csv",
                        required: true, class: "hidden",
                        data: {
                          bank_statement_upload_target: "file",
                          action: "change->bank-statement-upload#fileChanged"
                        })
                end

                # ── File preview (hidden until a valid file is chosen) ─────────
                div(class: "rounded-xl border border-gray-200 bg-gray-50 px-4 py-3 " \
                           "grid grid-cols-3 gap-3 text-center",
                    hidden: true,
                    data: { bank_statement_upload_target: "preview" }) do
                  preview_stat("Date range",     "dateRange")
                  preview_stat("Rows",           "rowCount")
                  preview_stat("Net movement",   "netMovement")
                end

                # ── Error message ──────────────────────────────────────────────
                p(class: "text-[12.5px] text-red-600 font-medium", hidden: true,
                  data: { bank_statement_upload_target: "error" })

                # ── Statement date (auto-filled, but editable) ─────────────────
                div do
                  p(class: "#{TEXT_LABEL} mb-1.5") { plain "Statement date" }
                  input(type: "date", name: "statement_date",
                        required: true, class: INPUT_FIELD,
                        data: { bank_statement_upload_target: "dateField" })
                  p(class: "#{TYPE_CAPTION} mt-1") do
                    plain "Auto-filled from the latest date in the file. Adjust if needed."
                  end
                end

                # ── Balances ───────────────────────────────────────────────────
                div(class: "grid grid-cols-2 gap-3") do
                  ghs_field("Opening balance", :opening_balance,
                            placeholder: "0.00", value: "0",
                            target: "openingBalanceField")
                  ghs_field("Closing balance", :closing_balance,
                            placeholder: "e.g. 98 000.00",
                            target: "closingBalanceField")
                end
              end
            end

            div(class: MODAL_FOOT) do
              render UI::Button.new(variant: :secondary, type: "button",
                                   data: { action: "click->modal#close" }) { plain "Cancel" }
              render UI::Button.new(variant: :primary, type: "submit",
                                   disabled: true,
                                   data: { bank_statement_upload_target: "submitBtn" }) do
                render UI::Icon.new(:upload, class: ICON_SM)
                plain "Import statement"
              end
            end
          end
        end
      end

      private

      def preview_stat(label_text, target_name)
        div do
          p(class: TYPE_CAPTION) { plain label_text }
          p(class: "text-[13px] font-semibold text-gray-800 mt-0.5 truncate",
            data: { bank_statement_upload_target: target_name }) { plain "—" }
        end
      end

      def ghs_field(label_text, name, placeholder: nil, value: nil, target: nil)
        div do
          p(class: "#{TEXT_LABEL} mb-1.5") { plain label_text }
          div(class: "relative") do
            span(class: "absolute left-3.5 top-1/2 -translate-y-1/2 px-2 py-0.5 rounded " \
                        "bg-gray-100 #{TYPE_CAPTION} font-semibold pointer-events-none select-none") do
              plain "GHS"
            end
            input_attrs = {
              type: "number", name: name.to_s, value: value,
              step: "0.01", min: "0", placeholder: placeholder,
              class: "#{INPUT_FIELD} !pl-16 font-mono text-[13.5px] tabular-nums"
            }
            input_attrs = input_attrs.merge(
              data: { bank_statement_upload_target: target }
            ) if target
            input(**input_attrs)
          end
        end
      end
    end
  end
end
