# frozen_string_literal: true

module Onboarding
  module Steps
    class ProfileStep < ApplicationComponent
      include UI::Theme

      BUSINESS_TYPES = [
        ["Sole Proprietorship", "sole_proprietorship"],
        ["Partnership",         "partnership"],
        ["Limited Liability Company (LLC)", "llc"],
        ["Private Limited Company", "private_limited"],
        ["Public Limited Company",  "public_limited"],
        ["Non-Governmental Organisation", "ngo"]
      ].freeze

      REGISTRATION_TYPES = [
        ["Registrar General's Department (RGD)", "rgd"],
        ["Ghana Revenue Authority (GRA)",         "gra"],
        ["Other",                                 "other"]
      ].freeze

      CATEGORIES = [
        ["E-commerce & Retail", "ecommerce_retail"],
        ["Food & Beverage",     "food_beverage"],
        ["Professional Services", "professional_services"],
        ["Education",            "education"],
        ["Healthcare",           "healthcare"],
        ["Travel & Hospitality", "travel_hospitality"],
        ["Entertainment & Media", "entertainment_media"],
        ["Non-profit / NGO",     "nonprofit"],
        ["Other",                "other"]
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
            step:        "1 of 5"
          )

          form(action: update_kyb_profile_path, method: :post, class: "p-6 space-y-5") do
            input(type: "hidden", name: "_method", value: "patch")
            csrf_meta_tags_field

            div(class: "grid grid-cols-1 sm:grid-cols-2 gap-5") do
              form_field(
                name:     "business_type",
                label:    "Business Type",
                required: true,
                hint:     "Select the legal structure of your business."
              ) do
                select_input("business_type", BUSINESS_TYPES, @merchant["business_type"])
              end

              form_field(
                name:  "registration_type",
                label: "Registration Authority",
                hint:  "Where your business is registered."
              ) do
                select_input("registration_type", REGISTRATION_TYPES, @merchant["registration_type"])
              end

              form_field(
                name:  "category",
                label: "Business Category",
                hint:  "What best describes your core business activity?"
              ) do
                select_input("category", CATEGORIES, @merchant["category"])
              end

              form_field(
                name:  "tin",
                label: "Tax Identification Number (TIN)",
                hint:  "Your Ghana Revenue Authority TIN."
              ) do
                input(
                  type:        "text",
                  name:        "tin",
                  value:       @merchant["tin"],
                  placeholder: "C0000000000",
                  class:       input_class
                )
              end
            end

            step_footer(next_label: "Save & Continue")
          end
        end
      end

      private

      def step_header(title:, description:, step:)
        div(class: "px-6 py-5 border-b", style: "border-color: #{colors[:border]}") do
          div(class: "flex items-center justify-between mb-1") do
            h2(class: "text-base font-semibold", style: "color: #{colors[:text_primary]}") { title }
            span(class: "text-xs font-medium px-2 py-0.5 rounded-full",
                 style: "background: #{colors[:surface_subtle]}; color: #{colors[:text_muted]}") { step }
          end
          p(class: "text-sm", style: "color: #{colors[:text_secondary]}") { description }
        end
      end

      def form_field(name:, label:, required: false, hint: nil, &block)
        div do
          div(class: "flex items-baseline justify-between mb-1.5") do
            label(for: name, class: "block text-sm font-medium",
                  style: "color: #{colors[:text_primary]}") do
              plain label
              sup(class: "text-red-500 ml-0.5") { "*" } if required
            end
          end
          yield
          p(class: "mt-1 text-xs", style: "color: #{colors[:text_muted]}") { hint } if hint
        end
      end

      def select_input(name, options, selected_value)
        select(name: name, id: name, class: input_class) do
          option(value: "") { "Select…" }
          options.each do |label, value|
            opt = option(value: value) { label }
            opt["selected"] = "selected" if selected_value == value
          end
        end
      end

      def step_footer(next_label: "Save & Continue")
        div(class: "pt-2 flex justify-end") do
          button(
            type:  "submit",
            class: "inline-flex items-center px-5 py-2.5 rounded-lg text-sm font-medium text-white transition-colors",
            style: "background: #{colors[:brand_primary]}"
          ) { next_label }
        end
      end

      def input_class
        "w-full rounded-lg border px-3 py-2 text-sm focus:outline-none focus:ring-2 " \
          "transition-colors #{colors_style_for_input}"
      end

      def colors_style_for_input
        "border-#{colors[:border]} bg-#{colors[:surface]} text-#{colors[:text_primary]}"
      end

      def csrf_meta_tags_field
        input(type: "hidden", name: "authenticity_token",
              value: form_authenticity_token)
      end
    end
  end
end
