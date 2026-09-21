# frozen_string_literal: true

module Onboarding
  module Steps
    class SettlementStep < ApplicationComponent
      include UI::Theme

      NETWORKS = [
        ["MTN Mobile Money",     "mtn"],
        ["Vodafone Cash",        "vodafone"],
        ["AirtelTigo Money",     "airteltigo"]
      ].freeze

      def initialize(progress:)
        @progress   = progress
        @settlement = progress.settlement || {}
      end

      def view_template
        div do
          step_header

          div(class: "p-6 space-y-6") do
            settlement_mode_tabs
          end
        end
      end

      private

      def step_header
        div(class: "px-6 py-5 border-b", style: "border-color: #{colors[:border]}") do
          div(class: "flex items-center justify-between mb-1") do
            h2(class: "text-base font-semibold", style: "color: #{colors[:text_primary]}") do
              "Settlement Account"
            end
            span(class: "text-xs font-medium px-2 py-0.5 rounded-full",
                 style: "background: #{colors[:surface_subtle]}; color: #{colors[:text_muted]}") do
              "3 of 5"
            end
          end
          p(class: "text-sm", style: "color: #{colors[:text_secondary]}") do
            "Where should we send your settlement funds? Choose between Mobile Money or a bank account."
          end
        end
      end

      def settlement_mode_tabs
        has_momo = @settlement["settlement_msisdn"].present?
        has_bank = @settlement["settlement_account_number"].present?
        active   = has_bank ? "bank" : "momo"

        div(data: { controller: "tabs" }) do
          tab_header(active)
          momo_form(active == "momo")
          bank_form(active == "bank")
        end
      end

      def tab_header(active)
        div(class: "flex gap-1 p-1 rounded-lg mb-6",
            style: "background: #{colors[:surface_subtle]}") do
          tab_button("momo", "Mobile Money", active == "momo")
          tab_button("bank", "Bank Account", active == "bank")
        end
      end

      def tab_button(key, label_text, is_active)
        button(
          type:  "button",
          class: "flex-1 py-2 px-4 rounded-md text-sm font-medium transition-all",
          style: is_active ?
                   "background: #{colors[:surface]}; color: #{colors[:brand_primary]}; box-shadow: 0 1px 2px rgba(0,0,0,0.06)" :
                   "color: #{colors[:text_muted]}",
          data: { action: "click->tabs#switch", tabs_target: "tab", tab_key: key }
        ) { label_text }
      end

      def momo_form(visible)
        form(
          action:  update_kyb_settlement_path,
          method:  :post,
          class:   visible ? "" : "hidden",
          data:    { tabs_target: "panel", tab_key: "momo" }
        ) do
          input(type: "hidden", name: "_method", value: "patch")
          csrf_token_input

          div(class: "space-y-4") do
            div do
              label(for: "settlement_msisdn", class: "block text-sm font-medium mb-1.5",
                    style: "color: #{colors[:text_primary]}") { "Mobile Money Number" }
              input(
                type:        "tel",
                name:        "settlement_msisdn",
                id:          "settlement_msisdn",
                value:       @settlement["settlement_msisdn"],
                placeholder: "+233 24 000 0000",
                class:       input_class
              )
              p(class: "mt-1 text-xs", style: "color: #{colors[:text_muted]}") do
                "Enter the number registered with your mobile money wallet."
              end
            end

            info_callout("Settlements are sent within 1–3 business days of the batch cutoff.")
            step_footer("bank")
          end
        end
      end

      def bank_form(visible)
        form(
          action:  update_kyb_settlement_path,
          method:  :post,
          class:   visible ? "" : "hidden",
          data:    { tabs_target: "panel", tab_key: "bank" }
        ) do
          input(type: "hidden", name: "_method", value: "patch")
          csrf_token_input

          div(class: "space-y-4") do
            div do
              label(for: "settlement_bank_code", class: "block text-sm font-medium mb-1.5",
                    style: "color: #{colors[:text_primary]}") { "Bank" }
              input(
                type:        "text",
                name:        "settlement_bank_code",
                id:          "settlement_bank_code",
                value:       @settlement["settlement_bank_code"],
                placeholder: "Bank code (e.g. GCB001)",
                class:       input_class
              )
            end

            div do
              label(for: "settlement_account_number", class: "block text-sm font-medium mb-1.5",
                    style: "color: #{colors[:text_primary]}") { "Account Number" }
              input(
                type:        "text",
                name:        "settlement_account_number",
                id:          "settlement_account_number",
                value:       @settlement["settlement_account_number"],
                placeholder: "1234567890",
                class:       input_class
              )
            end

            div do
              label(for: "settlement_account_name", class: "block text-sm font-medium mb-1.5",
                    style: "color: #{colors[:text_primary]}") { "Account Name" }
              input(
                type:        "text",
                name:        "settlement_account_name",
                id:          "settlement_account_name",
                value:       @settlement["settlement_account_name"],
                class:       input_class
              )
            end

            info_callout("Bank settlements may take 2–5 business days to process.")
            step_footer("contact")
          end
        end
      end

      def info_callout(text)
        div(class: "rounded-lg px-4 py-3 text-sm",
            style: "background: #{colors[:brand_subtle]}; color: #{colors[:brand_primary]}") do
          plain text
        end
      end

      def step_footer(back_step)
        div(class: "pt-2 flex justify-between items-center") do
          a(href: verify_step_path(back_step), class: "text-sm",
            style: "color: #{colors[:text_muted]}") { "← Back" }
          button(
            type:  "submit",
            class: "inline-flex items-center px-5 py-2.5 rounded-lg text-sm font-medium text-white",
            style: "background: #{colors[:brand_primary]}"
          ) { "Save & Continue" }
        end
      end

      def input_class
        "w-full rounded-lg border px-3 py-2 text-sm focus:outline-none focus:ring-2 transition-colors"
      end

      def csrf_token_input
        input(type: "hidden", name: "authenticity_token",
              value: form_authenticity_token)
      end
    end
  end
end
