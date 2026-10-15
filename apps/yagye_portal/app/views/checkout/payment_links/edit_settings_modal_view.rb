# frozen_string_literal: true

module Checkout
  module PaymentLinks
    class EditSettingsModalView < ApplicationComponent
      include UI::Theme

      METHODS = [
        { value: "mobile_money",  label: "Mobile Money",  detail: "MTN MoMo, Telecel, AirtelTigo" },
        { value: "card",          label: "Card",           detail: "Visa and Mastercard" },
        { value: "bank_transfer", label: "Bank transfer",  detail: "Direct bank-to-bank" }
      ].freeze

      def initialize(link:)
        @link    = link
        @methods = Array(@link["allowed_methods"])
        @id      = @link["id"]
      end

      def view_template
        div(class: MODAL_HEAD) do
          p(class: TYPE_TITLE) { plain "Edit settings" }
          p(class: "#{TYPE_CAPTION} mt-[3px]") { plain "Payment methods, collect fields, usage limits and expiry." }
        end

        form(
          id:     "edit-settings-form",
          action: payment_link_settings_path(@id),
          method: "post"
        ) do
          input(type: "hidden", name: "_method",            value: "patch")
          input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)

          div(class: MODAL_BODY) do
            div(class: "flex flex-col gap-5") do
              methods_section
              collect_section
              usage_section
            end
          end

          div(class: MODAL_FOOT) do
            a(href: payment_link_path(@id),
              data:  { turbo_frame: "_top" },
              class: BTN_SECONDARY) { plain "Cancel" }
            button(type: "submit", class: BTN_PRIMARY) { plain "Save settings" }
          end
        end
      end

      private

      def section_label(text)
        p(class: "text-[10.5px] font-bold uppercase tracking-[0.08em] text-gray-500 mb-2") { plain text }
      end

      def methods_section
        div do
          section_label("Payment methods")
          p(class: "#{TYPE_CAPTION} mb-3") { plain "At least one method must remain enabled." }
          div(class: "flex flex-col gap-[6px]") do
            METHODS.each { |m| method_row(m) }
          end
        end
      end

      def method_row(m)
        enabled = @methods.include?(m[:value])
        div(class: "flex items-center gap-2.5 px-3 py-2.5 rounded-[10px] border border-gray-100 hover:border-gray-200 transition-colors") do
          input(type: "checkbox",
                name: "allowed_methods[]",
                value: m[:value],
                id:   "sm_#{m[:value]}",
                class: "w-[14px] h-[14px] rounded flex-shrink-0 cursor-pointer",
                style: "accent-color:#{BRAND}",
                **(enabled ? { checked: true } : {}))
          div do
            label(for: "sm_#{m[:value]}",
                  class: "block text-[13px] font-semibold text-gray-800 cursor-pointer leading-tight") { plain m[:label] }
            p(class: "text-[11px] text-gray-400 leading-tight mt-[1px]") { plain m[:detail] }
          end
        end
      end

      def collect_section
        div do
          section_label("Collect from customer")
          div(class: "flex flex-col gap-[6px]") do
            collect_row("collect_email", "Email address",  @link["collect_email"])
            collect_row("collect_phone", "Phone number",   @link["collect_phone"])
            collect_row("collect_name",  "Full name",      @link["collect_name"])
          end
        end
      end

      def collect_row(name, label_text, checked)
        div(class: "flex items-center gap-2.5 px-3 py-2.5 rounded-[10px] border border-gray-100 hover:border-gray-200 transition-colors") do
          input(type: "checkbox",
                name: name,
                value: "1",
                id:   name,
                class: "w-[14px] h-[14px] rounded flex-shrink-0 cursor-pointer",
                style: "accent-color:#{BRAND}",
                **(checked ? { checked: true } : {}))
          label(for: name,
                class: "block text-[13px] font-semibold text-gray-800 cursor-pointer leading-tight") { plain label_text }
        end
      end

      def usage_section
        return unless @link["reusable"]

        div do
          section_label("Usage limits & expiry")
          div(class: "flex flex-col gap-3") do
            div do
              label(class: "block text-[11px] font-semibold text-gray-600 mb-[5px]") { plain "Maximum uses" }
              input(type:        "number",
                    name:        "max_uses",
                    min:         "1",
                    value:       @link["max_uses"],
                    placeholder: "Leave blank for unlimited",
                    class:       INPUT_FIELD)
              p(class: "#{TYPE_CAPTION} mt-1") { plain "Blank = no limit" }
            end
            div do
              label(class: "block text-[11px] font-semibold text-gray-600 mb-[5px]") { plain "Link expiry" }
              expiry_val = @link["expires_at"].present? ? Time.parse(@link["expires_at"]).strftime("%Y-%m-%dT%H:%M") : nil rescue nil
              input(type:  "datetime-local",
                    name:  "expires_at",
                    value: expiry_val,
                    class: INPUT_FIELD)
              p(class: "#{TYPE_CAPTION} mt-1") { plain "Optional — link stops working after this date." }
            end
          end
        end
      end
    end
  end
end
