# frozen_string_literal: true

module Payments
  module Reconciliation
    class UploadReportModalView < ApplicationComponent
      include UI::Theme

      def view_template
        turbo_frame_tag "drawer-frame", class: "flex flex-col min-h-full w-full" do
          div(class: "#{DRAWER_HEAD} flex-shrink-0") do
            div(class: "flex items-center gap-3 min-w-0") do
              div(class: "w-8 h-8 rounded-lg flex items-center justify-center flex-shrink-0",
                  style: "background:#{TINT_BRAND}") do
                span(class: "flex w-[14px] h-[14px]", style: "color:#{BRAND}") do
                  render UI::Icon.new(:upload, class: "w-full h-full")
                end
              end
              div do
                p(class: TYPE_MICRO) { plain "Reconciliation" }
                p(class: "text-[14px] font-semibold", style: "color:var(--ink)") do
                  plain "Upload MNO settlement report"
                end
              end
            end
            button(type: "button", class: XBTN,
                   data: { action: "click->drawer#close" },
                   aria: { label: "Close" }) do
              render UI::Icon.new(:x, class: ICON_SM)
            end
          end

          form(action: reconciliation_upload_report_path,
               method: "post",
               enctype: "multipart/form-data",
               class: "flex flex-col flex-1",
               data: { controller: "upload-report" }) do
            input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
            input(type: "hidden", name: "mode", value: "live")
            input(type: "hidden", name: "currency", value: "GHS")

            div(class: "p-6 flex flex-col gap-4 flex-1") do
              p(class: TYPE_CAPTION) do
                plain "Select the CSV file received from the mobile money network. " \
                      "Provider and date are detected automatically from the file."
              end

              # File drop zone
              label(class: "flex flex-col items-center justify-center gap-2 px-4 py-8 " \
                           "border-2 border-dashed border-gray-200 rounded-xl bg-gray-50 " \
                           "hover:border-gray-300 hover:bg-gray-100 transition-colors cursor-pointer") do
                span(class: "w-8 h-8 text-gray-400") do
                  render UI::Icon.new(:upload, class: "w-full h-full")
                end
                p(class: "text-[13px] font-medium text-gray-700") { plain "Choose a CSV file" }
                p(class: TYPE_CAPTION) do
                  plain "Expected: SETTLEMENT_DATE · LINE_NO · CHARGE_REF · GROSS_PESEWAS · VALUE_DATE …"
                end
                input(type: "file", name: "csv_file", accept: ".csv,text/csv", required: true,
                      class: "hidden",
                      data: { upload_report_target: "file",
                              action: "change->upload-report#fileChanged" })
              end

              p(hidden: true,
                class: "text-[12.5px] text-red-600 bg-red-50 border border-red-100 " \
                       "rounded-lg px-3 py-2",
                data: { upload_report_target: "error" }) { }

              div(hidden: true,
                  class: "flex flex-col gap-3",
                  data: { upload_report_target: "preview" }) do
                div do
                  label(class: "#{TEXT_LABEL} block mb-1.5", for: "upload_provider") do
                    plain "Provider"
                  end
                  select(id: "upload_provider", name: "provider_code", required: true,
                         class: SELECT_FIELD,
                         data: { upload_report_target: "providerSelect" }) do
                    option(value: "") { plain "Select provider…" }
                    option(value: "mtn_gh") { plain "MTN Ghana" }
                    option(value: "vodafone_gh") { plain "Vodafone / Telecel Ghana" }
                    option(value: "airteltigo_gh") { plain "AirtelTigo Ghana" }
                    option(value: "simulator") { plain "Simulator (internal)" }
                  end
                end

                div(class: "grid grid-cols-3 gap-3") do
                  [ [ "Settlement date", "dateDisplay" ],
                    [ "Rows",            "lineCount" ],
                    [ "Net total",       "netTotal" ] ].each do |label, target|
                    div(class: "bg-gray-50 rounded-xl px-3 py-[10px]") do
                      p(class: "#{TYPE_MICRO} text-gray-500 mb-[3px]") { plain label }
                      p(class: "text-[13px] font-semibold text-gray-800",
                        data: { upload_report_target: target }) { plain "—" }
                    end
                  end
                end
              end
            end

            div(class: "sticky bottom-0 flex items-center justify-end gap-3 px-6 py-5 " \
                       "border-t border-gray-100 bg-white flex-shrink-0") do
              render UI::Button.new(variant: :secondary, type: "button",
                                   data: { action: "click->drawer#close" }) { plain "Cancel" }
              render UI::Button.new(variant: :primary, type: "submit",
                                   disabled: true,
                                   data: { upload_report_target: "submitBtn" }) do
                plain "Upload & reconcile"
              end
            end
          end
        end
      end
    end
  end
end
