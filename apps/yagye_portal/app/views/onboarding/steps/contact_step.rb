# frozen_string_literal: true

module Onboarding
  module Steps
    class ContactStep < ApplicationComponent
      include UI::Theme

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
            step:        "2 of 5"
          )

          form(action: update_kyb_contact_path, method: :post, class: "p-6 space-y-6") do
            input(type: "hidden", name: "_method", value: "patch")
            csrf_token_input

            section_label("Business Emails")
            div(class: "grid grid-cols-1 sm:grid-cols-2 gap-5") do
              text_field("general_email",   "General Email",   @contact["general_email"],   type: "email", hint: "Primary contact for correspondence")
              text_field("support_email",   "Support Email",   @contact["support_email"],   type: "email")
              text_field("disputes_email",  "Disputes Email",  @contact["disputes_email"],  type: "email")
            end

            section_label("Phone & Social")
            div(class: "grid grid-cols-1 sm:grid-cols-2 gap-5") do
              text_field("phone_number",      "Business Phone",     @contact["phone_number"],      type: "tel",  hint: "Include country code, e.g. +233 24 000 0000")
              text_field("whatsapp_number",   "WhatsApp Number",    @contact["whatsapp_number"],   type: "tel")
              text_field("website_url",       "Website",            @contact["website_url"],        type: "url",  hint: "https://yoursite.com")
              text_field("twitter_handle",    "X (Twitter) Handle", @contact["twitter_handle"],    placeholder: "@handle")
              text_field("facebook_username", "Facebook Username",  @contact["facebook_username"])
              text_field("instagram_handle",  "Instagram Handle",   @contact["instagram_handle"],  placeholder: "@handle")
            end

            section_label("Office Address")
            div(class: "grid grid-cols-1 sm:grid-cols-2 gap-5") do
              div do
                label_tag("country", "Country")
                select(name: "country", id: "country", class: input_class) do
                  option(value: "")  { "Select…" }
                  option(value: "GH", selected: @office["country"] == "GH") { "Ghana" }
                  option(value: "NG", selected: @office["country"] == "NG") { "Nigeria" }
                  option(value: "KE", selected: @office["country"] == "KE") { "Kenya" }
                end
              end
              text_field("region",         "Region",         @office["region"])
              text_field("city",           "City",           @office["city"])
              text_field("street_address", "Street Address", @office["street_address"])
              text_field("gps_address",    "GPS Address",    @office["gps_address"],    hint: "e.g. GH-123-4567")
            end

            step_footer
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

      def section_label(text)
        h3(class: "text-xs font-semibold uppercase tracking-wide pt-1",
           style: "color: #{colors[:text_muted]}") { text }
      end

      def text_field(name, label_text, value, type: "text", hint: nil, placeholder: nil)
        div do
          label(for: name, class: "block text-sm font-medium mb-1.5",
                style: "color: #{colors[:text_primary]}") { label_text }
          input(
            type:        type,
            name:        name,
            id:          name,
            value:       value,
            placeholder: placeholder,
            class:       input_class
          )
          p(class: "mt-1 text-xs", style: "color: #{colors[:text_muted]}") { hint } if hint
        end
      end

      def label_tag(for_attr, text)
        label(for: for_attr, class: "block text-sm font-medium mb-1.5",
              style: "color: #{colors[:text_primary]}") { text }
      end

      def step_footer
        div(class: "pt-2 flex justify-between items-center") do
          a(href: verify_step_path("profile"), class: "text-sm",
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
