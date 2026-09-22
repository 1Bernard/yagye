# frozen_string_literal: true

module Onboarding
  module Steps
    class ContactStep < ApplicationComponent
      include UI::Theme

      BRAND = UI::Theme::BRAND

      def initialize(progress:)
        @progress = progress
        @contact  = progress.contact || {}
        @office   = progress.office_address || {}
      end

      def view_template
        div do
          step_header(
            title:       "Contact Details",
            description: "How customers and your team can reach you, and where your business operates.",
            step:        "2 of 5",
            icon:        :mail
          )

          form(action: update_kyb_contact_path, method: :post) do
            input(type: "hidden", name: "_method", value: "patch")
            input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)

            div(class: "px-6 py-5 space-y-6") do
              section_label("Business Emails")
              div(class: "grid grid-cols-1 sm:grid-cols-2 gap-5") do
                text_field("general_email",  "General Email",  @contact["general_email"],  type: "email", hint: "Primary contact for correspondence")
                text_field("support_email",  "Support Email",  @contact["support_email"],  type: "email")
                text_field("disputes_email", "Disputes Email", @contact["disputes_email"], type: "email")
              end

              section_label("Phone & Social")
              div(class: "grid grid-cols-1 sm:grid-cols-2 gap-5") do
                text_field("phone_number",      "Business Phone",     @contact["phone_number"],      type: "tel",  hint: "Include country code, e.g. +233 24 000 0000")
                text_field("whatsapp_number",   "WhatsApp Number",    @contact["whatsapp_number"],   type: "tel")
                text_field("website_url",       "Website",            @contact["website_url"],       type: "url",  hint: "https://yoursite.com")
                text_field("twitter_handle",    "X (Twitter) Handle", @contact["twitter_handle"],    placeholder: "@handle")
                text_field("facebook_username", "Facebook Username",  @contact["facebook_username"])
                text_field("instagram_handle",  "Instagram Handle",   @contact["instagram_handle"],  placeholder: "@handle")
              end

              section_label("Office Address")
              div(class: "grid grid-cols-1 sm:grid-cols-2 gap-5") do
                div do
                  label(for: "country", class: "block text-[13px] font-medium text-gray-700 mb-1.5") { "Country" }
                  select(name: "country", id: "country", class: SELECT_FIELD) do
                    option(value: "")                                                  { "Select…" }
                    option(value: "GH", selected: @office["country"] == "GH" || nil) { "Ghana"   }
                    option(value: "NG", selected: @office["country"] == "NG" || nil) { "Nigeria" }
                    option(value: "KE", selected: @office["country"] == "KE" || nil) { "Kenya"   }
                  end
                end
                text_field("region",         "Region",         @office["region"])
                text_field("city",           "City",           @office["city"])
                text_field("street_address", "Street Address", @office["street_address"])
                text_field("gps_address",    "GPS Address",    @office["gps_address"], hint: "e.g. GH-123-4567")
              end
            end

            step_footer(back_step: "profile")
          end
        end
      end

      private

      def step_header(title:, description:, step:, icon: :mail)
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

      def section_label(text)
        p(class: "#{TYPE_HEADING} pt-1 pb-0.5") { plain text }
      end

      def text_field(name, label_text, value, type: "text", hint: nil, placeholder: nil)
        div do
          label(for: name, class: "block text-[13px] font-medium text-gray-700 mb-1.5") { plain label_text }
          input(
            type:        type,
            name:        name,
            id:          name,
            value:       value,
            placeholder: placeholder,
            class:       INPUT_FIELD
          )
          p(class: "#{TYPE_CAPTION} mt-1") { plain hint } if hint
        end
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
