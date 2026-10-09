# frozen_string_literal: true

module Onboarding
  module Steps
    class SettlementStep < ApplicationComponent
      include UI::Theme

      BRAND = UI::Theme::BRAND

      GHANA_BANKS = [
        [ "Ghana Commercial Bank (GCB)",  "GCB001" ],
        [ "Ecobank Ghana",                "ECO001" ],
        [ "Stanbic Bank Ghana",           "STD001" ],
        [ "Fidelity Bank Ghana",          "FBL001" ],
        [ "Standard Chartered Bank",      "SCB001" ],
        [ "Absa Bank Ghana",              "ABS001" ],
        [ "CalBank",                      "CAL001" ],
        [ "United Bank for Africa (UBA)", "UBA001" ],
        [ "Access Bank Ghana",            "ACC001" ],
        [ "Zenith Bank Ghana",            "ZEN001" ],
        [ "Republic Bank Ghana",          "REP001" ],
        [ "Agricultural Development Bank", "ADB001" ],
        [ "NIB Bank",                     "NIB001" ],
        [ "Consolidated Bank Ghana (CBG)", "CBG001" ],
        [ "First Atlantic Bank",          "FAB001" ],
        [ "Prudential Bank",              "PRU001" ],
        [ "OmniBSIC Bank",                "OMS001" ],
        [ "Societe Generale Ghana",       "SOG001" ]
      ].freeze

      def initialize(progress:)
        @progress   = progress
        @settlement = progress.settlement || {}
      end

      def view_template
        has_bank = @settlement["settlement_account_number"].present?
        has_momo = @settlement["settlement_msisdn"].present?
        active   = has_bank && !has_momo ? "bank" : "momo"

        div do
          step_header

          div(data: { controller: "tabs", tabs_active_value: active }) do
            div(class: "px-6 pt-5") do
              tab_header(active)
            end
            momo_form(active == "momo")
            bank_form(active == "bank")
          end
        end
      end

      private

      def step_header
        div(class: "px-6 py-5 border-b border-gray-100") do
          div(class: "flex items-start justify-between gap-4 mb-3") do
            div(
              class: "w-9 h-9 rounded-xl flex items-center justify-center flex-shrink-0",
              style: "background: rgba(61,71,245,0.08); border: 1px solid rgba(61,71,245,0.16)"
            ) do
              span(class: "flex w-[15px] h-[15px]", style: "color: #{BRAND}") do
                render UI::Icon.new(:trending_up, class: "w-full h-full")
              end
            end
            span(
              class: "text-[11px] font-semibold px-[9px] py-[3px] rounded-full flex-shrink-0 mt-[5px]",
              style: "background: rgba(61,71,245,0.08); color: #{BRAND}"
            ) { plain "3 of 5" }
          end
          p(class: TYPE_TITLE) { plain "Settlement Account" }
          p(class: "#{TYPE_CAPTION} mt-[3px]") do
            plain "Where should we send your settlement funds? Choose Mobile Money or a bank account."
          end
        end
      end

      def tab_header(active)
        div(class: "flex gap-1 p-1 rounded-xl bg-gray-100 mb-4") do
          tab_btn("momo", "Mobile Money", active == "momo")
          tab_btn("bank", "Bank Account", active == "bank")
        end
      end

      def tab_btn(key, text, is_active)
        button(
          type:  "button",
          class: "flex-1 py-2 px-4 rounded-lg text-[13px] font-medium transition-all",
          style: is_active ?
                   "background: white; color: #{BRAND}; box-shadow: 0 1px 2px rgba(0,0,0,0.08)" :
                   "color: #6B7280",
          data: { action: "click->tabs#show", tabs_target: "tab", tabs_panel_param: key }
        ) { plain text }
      end

      def momo_form(visible)
        form(
          action:  update_kyb_settlement_path,
          method:  :post,
          hidden:  !visible,
          data:    { tabs_target: "panel", tabs_id: "momo" }
        ) do
          input(type: "hidden", name: "_method", value: "patch")
          input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)

          div(class: "px-6 py-5 space-y-4") do
            div do
              label(for: "settlement_msisdn", class: "block text-[13px] font-medium text-gray-700 mb-1.5") do
                plain "Mobile Money Number"
              end
              input(
                type:        "tel",
                name:        "settlement_msisdn",
                id:          "settlement_msisdn",
                value:       @settlement["settlement_msisdn"],
                placeholder: "+233 24 000 0000",
                class:       INPUT_FIELD
              )
              p(class: "#{TYPE_CAPTION} mt-1") { plain "Enter the number registered with your mobile money wallet." }
            end

            info_callout("Settlements are sent within 1–3 business days of the batch cutoff.")
          end

          step_footer(back_step: "contact")
        end
      end

      def bank_form(visible)
        form(
          action:  update_kyb_settlement_path,
          method:  :post,
          hidden:  !visible,
          data:    { tabs_target: "panel", tabs_id: "bank" }
        ) do
          input(type: "hidden", name: "_method", value: "patch")
          input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)

          div(class: "px-6 py-5 space-y-4") do
            div do
              label(for: "settlement_bank_code", class: "block text-[13px] font-medium text-gray-700 mb-1.5") do
                plain "Bank"
              end
              select(name: "settlement_bank_code", id: "settlement_bank_code", class: SELECT_FIELD) do
                option(value: "") { plain "Select your bank…" }
                GHANA_BANKS.each do |lbl, value|
                  option(value: value, selected: @settlement["settlement_bank_code"] == value || nil) { plain lbl }
                end
              end
            end

            div do
              label(for: "settlement_account_number", class: "block text-[13px] font-medium text-gray-700 mb-1.5") do
                plain "Account Number"
              end
              input(
                type:        "text",
                name:        "settlement_account_number",
                id:          "settlement_account_number",
                value:       @settlement["settlement_account_number"],
                placeholder: "1234567890",
                class:       INPUT_FIELD
              )
            end

            div do
              label(for: "settlement_account_name", class: "block text-[13px] font-medium text-gray-700 mb-1.5") do
                plain "Account Name"
              end
              input(
                type:  "text",
                name:  "settlement_account_name",
                id:    "settlement_account_name",
                value: @settlement["settlement_account_name"],
                class: INPUT_FIELD
              )
            end

            info_callout("Bank settlements may take 2–5 business days to process.")
          end

          step_footer(back_step: "contact")
        end
      end

      def info_callout(text)
        div(
          class: "rounded-xl px-4 py-3 text-[13px]",
          style: "background: rgba(61,71,245,0.06); color: #{BRAND}"
        ) { plain text }
      end

      def step_footer(back_step: nil)
        div(class: "px-6 py-4 border-t border-gray-100 flex items-center justify-between") do
          if back_step
            a(href: verify_step_path(back_step), class: BTN_SECONDARY) do
              render UI::Icon.new(:arrow_left, class: ICON_SM)
              plain "Back"
            end
          else
            div
          end
          button(type: "submit", class: BTN_PRIMARY) do
            plain "Save & Continue"
            render UI::Icon.new(:arrow_right, class: ICON_SM)
          end
        end
      end
    end
  end
end
