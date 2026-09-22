# frozen_string_literal: true

module Onboarding
  module Steps
    class ProfileStep < ApplicationComponent
      include UI::Theme

      BRAND = UI::Theme::BRAND

      BUSINESS_TYPES = [
        ["Sole Proprietorship",                  "sole_proprietorship"],
        ["Partnership",                           "partnership"],
        ["Limited Liability Company (LLC)",       "llc"],
        ["Private Limited Company",               "private_limited"],
        ["Public Limited Company",                "public_limited"],
        ["Non-Governmental Organisation",         "ngo"]
      ].freeze

      REGISTRATION_TYPES = [
        ["Registrar General's Department (RGD)", "rgd"],
        ["Ghana Revenue Authority (GRA)",         "gra"],
        ["Other",                                 "other"]
      ].freeze

      CATEGORIES = [
        ["E-commerce & Retail",        "ecommerce_retail"],
        ["Food & Beverage",            "food_beverage"],
        ["Professional Services",      "professional_services"],
        ["Education",                  "education"],
        ["Healthcare",                 "healthcare"],
        ["Travel & Hospitality",       "travel_hospitality"],
        ["Entertainment & Media",      "entertainment_media"],
        ["Non-profit / NGO",           "nonprofit"],
        ["Other",                      "other"]
      ].freeze

      def initialize(progress:)
        @progress = progress
        @merchant = progress.merchant
      end

      def view_template
        div do
          step_header(
            title:       "Business Profile",
            description: "Tell us about your business — this information will be used to verify your identity.",
            step:        "1 of 5",
            icon:        :building
          )

          form(action: update_kyb_profile_path, method: :post) do
            input(type: "hidden", name: "_method", value: "patch")
            input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)

            div(class: "px-6 py-5 space-y-5") do
              div(class: "grid grid-cols-1 sm:grid-cols-2 gap-5") do
                form_field(name: "business_type", label: "Business Type", required: true,
                           hint: "Select the legal structure of your business.") do
                  select_input("business_type", BUSINESS_TYPES, @merchant["business_type"])
                end

                form_field(name: "registration_type", label: "Registration Authority",
                           hint: "Where your business is registered.") do
                  select_input("registration_type", REGISTRATION_TYPES, @merchant["registration_type"])
                end

                form_field(name: "category", label: "Business Category",
                           hint: "What best describes your core business activity?") do
                  select_input("category", CATEGORIES, @merchant["category"])
                end

                form_field(name: "tin", label: "Tax Identification Number (TIN)",
                           hint: "Your Ghana Revenue Authority TIN.") do
                  input(type: "text", name: "tin", id: "tin",
                        value: @merchant["tin"], placeholder: "C0000000000",
                        class: INPUT_FIELD)
                end
              end
            end

            step_footer(submit_label: "Save & Continue")
          end
        end
      end

      private

      def step_header(title:, description:, step:, icon: :building)
        div(class: "px-6 py-5 border-b border-gray-100") do
          div(class: "flex items-start justify-between gap-4 mb-3") do
            div(
              class: "w-9 h-9 rounded-xl flex items-center justify-center flex-shrink-0",
              style: "background: rgba(61,71,245,0.08); border: 1px solid rgba(61,71,245,0.16)"
            ) do
              span(class: "flex w-[15px] h-[15px]", style: "color: #{BRAND}") do
                render UI::Icon.new(icon, class: "w-full h-full")
              end
            end
            span(
              class: "text-[11px] font-semibold px-[9px] py-[3px] rounded-full flex-shrink-0 mt-[5px]",
              style: "background: rgba(61,71,245,0.08); color: #{BRAND}"
            ) { plain step }
          end
          p(class: TYPE_TITLE) { plain title }
          p(class: "#{TYPE_CAPTION} mt-[3px]") { plain description }
        end
      end

      def form_field(name:, label:, required: false, hint: nil, &block)
        div do
          div(class: "flex items-baseline gap-1 mb-1.5") do
            label(for: name, class: "block text-[13px] font-medium text-gray-700") { plain label }
            sup(class: "text-red-500 ml-0.5") { "*" } if required
          end
          yield
          p(class: "#{TYPE_CAPTION} mt-1") { plain hint } if hint
        end
      end

      def select_input(name, options, selected_value)
        select(name: name, id: name, class: SELECT_FIELD) do
          option(value: "") { plain "Select…" }
          options.each do |lbl, value|
            option(value: value, selected: selected_value == value || nil) { plain lbl }
          end
        end
      end

      def step_footer(back_step: nil, submit_label: "Save & Continue")
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
            plain submit_label
            render UI::Icon.new(:arrow_right, class: ICON_SM)
          end
        end
      end
    end
  end
end
