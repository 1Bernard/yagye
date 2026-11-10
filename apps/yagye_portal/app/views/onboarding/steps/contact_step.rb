# frozen_string_literal: true

module Onboarding
  module Steps
    class ContactStep < ApplicationComponent
      include UI::Theme

      BRAND = UI::Theme::BRAND

      COUNTRIES = [
        [ "Ghana",   "GH" ],
        [ "Nigeria", "NG" ],
        [ "Kenya",   "KE" ]
      ].freeze

      def initialize(progress:)
        @progress   = progress
        @contact    = progress.contact || {}
        @registered = progress.registered_address || {}
        @office     = progress.office_address || {}
      end

      def view_template
        div do
          step_header

          form(action: update_kyb_contact_path, method: :post) do
            input(type: "hidden", name: "_method",            value: "patch")
            input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)

            div(class: "px-6 py-5 space-y-4") do
              emails_card
              phone_card
              addresses_card
            end

            step_footer(back_step: "profile")
          end
        end
      end

      private

      # ── Cards ──────────────────────────────────────────────────────────────

      def emails_card
        support_open = @contact["support_email"].present? || @contact["disputes_email"].present?

        section_card do
          div(class: "p-5") do
            card_heading("Business Emails")
            div(class: "mt-4") do
              text_field("general_email", "General Email", @contact["general_email"],
                         type: "email", required: true,
                         hint: "Primary contact for correspondence and account notices")
            end
          end

          accordion_row("Support & disputes emails", open: support_open) do
            div(class: "px-5 pb-5 grid grid-cols-1 sm:grid-cols-2 gap-4") do
              text_field("support_email",  "Support Email",  @contact["support_email"],
                         type: "email", hint: "Where customers send support queries")
              text_field("disputes_email", "Disputes Email", @contact["disputes_email"],
                         type: "email", hint: "For chargebacks and payment disputes")
            end
          end
        end
      end

      def phone_card
        social_open = %w[whatsapp_number twitter_handle facebook_username instagram_handle]
                        .any? { |k| @contact[k].present? }

        section_card do
          div(class: "p-5 space-y-4") do
            card_heading("Phone & Online Presence")
            div(class: "grid grid-cols-1 sm:grid-cols-2 gap-4") do
              text_field("phone_number", "Business Phone", @contact["phone_number"],
                         type: "tel", hint: "Include country code, e.g. +233 24 000 0000")
              text_field("website_url",  "Website",        @contact["website_url"],
                         type: "url",  hint: "https://yoursite.com")
            end
          end

          accordion_row("Social media & messaging", open: social_open) do
            div(class: "px-5 pb-5 grid grid-cols-1 sm:grid-cols-2 gap-4") do
              text_field("whatsapp_number",   "WhatsApp Number",    @contact["whatsapp_number"],   type: "tel")
              text_field("twitter_handle",    "X (Twitter) Handle", @contact["twitter_handle"],    placeholder: "@handle")
              text_field("facebook_username", "Facebook Username",  @contact["facebook_username"])
              text_field("instagram_handle",  "Instagram Handle",   @contact["instagram_handle"],  placeholder: "@handle")
            end
          end
        end
      end

      def addresses_card
        same_as = @office.blank? || @office == @registered

        section_card do
          # Registered address ─────────────────────────────────────────────
          div(class: "p-5 space-y-4") do
            div do
              card_heading("Registered Address")
              p(class: "#{TYPE_CAPTION} mt-0.5") do
                plain "The legal address on your company registration certificate (RGD / GRA)."
              end
            end
            address_fields("registered", @registered)
          end

          # Office address — one disclosure controller wraps checkbox + panel
          div(
            class: "border-t border-gray-100 p-5 space-y-4",
            data:  {
              controller:            "disclosure",
              disclosure_open_value: (!same_as).to_s
            }
          ) do
            div(class: "flex items-start justify-between gap-3") do
              div do
                card_heading("Office Address")
                p(class: "#{TYPE_CAPTION} mt-0.5") { plain "Where your team actually operates." }
              end
              div(class: "flex items-center gap-2 flex-shrink-0 pt-0.5") do
                input(
                  type:    "checkbox",
                  id:      "office_same_as_registered",
                  name:    "office_same_as_registered",
                  value:   "1",
                  checked: same_as || nil,
                  class:   CHECKBOX_INPUT,
                  data:    { action: "change->disclosure#checkboxToggle" }
                )
                label(for: "office_same_as_registered",
                      class: "text-[12px] text-gray-500 select-none cursor-pointer whitespace-nowrap") do
                  plain "Same as registered"
                end
              end
            end

            # Panel hidden when checkbox is checked
            div(data: { disclosure_target: "panel" }, hidden: same_as) do
              address_fields("office", @office)
            end
          end
        end
      end

      # ── Primitives ──────────────────────────────────────────────────────────

      def section_card(&block)
        div(class: "rounded-xl border border-gray-100 overflow-hidden bg-white", &block)
      end

      def card_heading(text)
        p(class: "text-[13px] font-semibold text-gray-800") { plain text }
      end

      # Accordion using native <details>/<summary> — no JS required.
      # + icon rotates 45° to × via CSS group-open variant when expanded.
      def accordion_row(label, open:, &block)
        details(
          class: "group border-t border-indigo-100/60",
          open:  open || nil
        ) do
          summary(
            class: "flex items-center gap-2.5 w-full px-5 py-3 " \
                   "bg-indigo-50/30 hover:bg-indigo-50/70 transition-colors cursor-pointer " \
                   "list-none [&::-webkit-details-marker]:hidden"
          ) do
            span(
              class: "flex-shrink-0 w-[18px] h-[18px] rounded-full flex items-center justify-center " \
                     "border border-indigo-300 text-indigo-500 transition-transform duration-200 " \
                     "group-open:rotate-45"
            ) do
              render UI::Icon.new(:plus, class: "w-[9px] h-[9px]")
            end
            span(class: "text-[12.5px] font-medium text-indigo-600") { plain label }
          end

          yield
        end
      end

      # ── Address grid ──────────────────────────────────────────────────────

      def address_fields(prefix, addr)
        div(class: "grid grid-cols-1 sm:grid-cols-2 gap-4") do
          div do
            label(for: "#{prefix}_country",
                  class: "block text-[13px] font-medium text-gray-700 mb-1.5") { plain "Country" }
            select(name: "#{prefix}_country", id: "#{prefix}_country", class: SELECT_FIELD) do
              option(value: "") { plain "Select…" }
              COUNTRIES.each do |name, code|
                option(value: code, selected: addr["country"] == code || nil) { plain name }
              end
            end
          end
          text_field("#{prefix}_region",        "Region",         addr["region"])
          text_field("#{prefix}_city",           "City",           addr["city"])
          text_field("#{prefix}_street_address", "Street Address", addr["street_address"])
          div(class: "sm:col-span-2") do
            text_field("#{prefix}_gps_address", "GPS Address", addr["gps_address"],
                       hint: "e.g. GH-123-4567")
          end
        end
      end

      # ── Individual field ──────────────────────────────────────────────────

      def text_field(name, label_text, value, type: "text", hint: nil, placeholder: nil, required: false)
        div do
          div(class: "flex items-baseline gap-1 mb-1.5") do
            label(for: name, class: "block text-[13px] font-medium text-gray-700") { plain label_text }
            sup(class: "text-red-500 ml-0.5") { "*" } if required
          end
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

      # ── Step chrome ───────────────────────────────────────────────────────

      def step_header
        div(class: "px-6 py-5 border-b border-gray-100") do
          div(class: "flex items-start justify-between gap-4 mb-3") do
            div(
              class: "w-9 h-9 rounded-xl flex items-center justify-center flex-shrink-0",
              style: "background: rgba(61,71,245,0.08); border: 1px solid rgba(61,71,245,0.16)"
            ) do
              span(class: "flex w-[15px] h-[15px]", style: "color: #{BRAND}") do
                render UI::Icon.new(:mail, class: "w-full h-full")
              end
            end
            span(
              class: "text-[11px] font-semibold px-[9px] py-[3px] rounded-full flex-shrink-0 mt-[5px]",
              style: "background: rgba(61,71,245,0.08); color: #{BRAND}"
            ) { plain "2 of 5" }
          end
          p(class: TYPE_TITLE) { plain "Contact Details" }
          p(class: "#{TYPE_CAPTION} mt-[3px]") do
            plain "How customers and your team can reach you, and where your business is registered."
          end
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
