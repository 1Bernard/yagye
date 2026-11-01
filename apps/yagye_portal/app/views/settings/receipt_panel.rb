# frozen_string_literal: true

module Settings
  class ReceiptPanel < ApplicationComponent
    include UI::Theme

    FIELD_LABEL = "text-[12.5px] font-semibold text-gray-700 leading-tight"

    TOGGLES = [
      { key: "show_fee",        label: "Show fee amount",
        desc: "Display the Yagye processing fee on the customer receipt" },
      { key: "show_address",    label: "Show merchant address",
        desc: "Show your registered business address on the receipt" },
      { key: "show_phone",      label: "Show merchant phone",
        desc: "Show your support phone number on the receipt" },
      { key: "show_powered_by", label: "Show \"Powered by Yagye\"",
        desc: "Display the Yagye branding footer on receipts" }
    ].freeze

    def initialize(settings:)
      @settings = settings.is_a?(Hash) ? settings.transform_keys(&:to_s) : {}
    end

    def view_template
      form(action: settings_update_receipt_path, method: "post") do
        input(type: "hidden", name: "_method",            value: "patch")
        input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)

        div(class: "bg-white border border-gray-100 rounded-2xl overflow-hidden") do
          div(class: "px-6 py-5 border-b border-gray-100") do
            p(class: TYPE_TITLE) { plain "Receipt settings" }
            p(class: "#{TYPE_CAPTION} mt-[3px]") do
              plain "Configure what appears on the payment receipt sent to your customers."
            end
          end

          div(class: "px-6 py-5 border-b border-gray-100 flex flex-col gap-0") do
            p(class: "text-[10.5px] font-semibold text-gray-400 uppercase tracking-widest mb-4") do
              plain "Display options"
            end
            TOGGLES.each { |t| toggle_row(t) }
          end

          div(class: "px-6 py-5 border-b border-gray-100 flex flex-col gap-2") do
            label(for: "custom_note", class: FIELD_LABEL) { plain "Custom note" }
            textarea(
              name: "custom_note",
              id:   "custom_note",
              rows: 3,
              maxlength: 500,
              placeholder: "e.g. Thank you for shopping with us! Contact support@yourshop.com for help.",
              class: "#{INPUT_FIELD} resize-none"
            ) { plain @settings["custom_note"].to_s }
            p(class: FORM_HINT) do
              plain "Optional message printed at the bottom of every receipt. Max 500 characters."
            end
          end

          div(class: "px-6 py-4 bg-gray-50 border-t border-gray-100 flex justify-end") do
            render UI::Button.new(variant: :primary, type: "submit") do
              render UI::Icon.new(:check, class: ICON_SM)
              plain "Save receipt settings"
            end
          end
        end
      end
    end

    private

    def toggle_row(toggle)
      checked = @settings.key?(toggle[:key]) ? @settings[toggle[:key]] : true
      div(class: "flex items-start justify-between gap-6 py-[14px] border-b border-gray-50 last:border-0") do
        div(class: "flex flex-col gap-[3px]") do
          p(class: "text-[13.5px] font-medium text-gray-800") { plain toggle[:label] }
          p(class: "text-[12px] text-gray-400 leading-snug") { plain toggle[:desc] }
        end
        label(class: "relative inline-flex items-center cursor-pointer flex-shrink-0") do
          input(
            type:    "hidden",
            name:    toggle[:key],
            value:   "0"
          )
          input(
            type:    "checkbox",
            name:    toggle[:key],
            id:      toggle[:key],
            value:   "1",
            checked: checked,
            class:   "sr-only peer"
          )
          div(
            class: "w-10 h-[22px] bg-gray-200 peer-focus:outline-none rounded-full peer " \
                   "peer-checked:after:translate-x-[18px] after:content-[''] after:absolute " \
                   "after:top-[2px] after:left-[2px] after:bg-white after:rounded-full " \
                   "after:h-[18px] after:w-[18px] after:transition-all peer-checked:bg-brand-500"
          )
        end
      end
    end
  end
end
