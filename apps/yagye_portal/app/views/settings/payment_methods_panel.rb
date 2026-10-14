# frozen_string_literal: true

module Settings
  class PaymentMethodsPanel < ApplicationComponent
    include UI::Theme

    METHODS = [
      { key: "mobile_money",   label: "Mobile Money",   icon: :smartphone,   desc: "MTN MoMo, Telecel Cash, AirtelTigo Money" },
      { key: "card",           label: "Card",           icon: :credit_card,   desc: "Visa, Mastercard, and local debit cards" },
      { key: "bank_transfer",  label: "Bank Transfer",  icon: :bank,          desc: "Direct bank account transfers" }
    ].freeze

    def initialize(allowed_methods: nil)
      @allowed = Array(allowed_methods).presence || %w[mobile_money card bank_transfer]
    end

    def view_template
      div(class: "flex flex-col gap-5") do
        methods_card
      end
    end

    private

    def methods_card
      div(class: "bg-white border border-gray-100 rounded-2xl overflow-hidden") do
        div(class: "px-6 py-5 border-b border-gray-100") do
          p(class: TYPE_TITLE) { plain "Payment Methods" }
          p(class: "#{TYPE_CAPTION} mt-[3px]") do
            plain "Set the default payment methods for API-created checkout sessions. Overridden per payment link."
          end
        end

        form(action: settings_payment_methods_path, method: "post") do
          input(type: "hidden", name: "_method",            value: "patch")
          input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)

          div(class: "divide-y divide-gray-50") do
            METHODS.each { |m| method_row(m) }
          end

          div(class: "px-6 py-4 bg-gray-50 border-t border-gray-100 flex items-center justify-between gap-4") do
            p(class: TYPE_CAPTION) { plain "At least one method must remain enabled." }
            render UI::Button.new(variant: :primary, type: "submit") { plain "Save changes" }
          end
        end
      end
    end

    def method_row(m)
      enabled = @allowed.include?(m[:key])

      div(class: "px-6 py-4 flex items-center gap-4") do
        div(class: "w-9 h-9 rounded-xl flex items-center justify-center flex-shrink-0",
            style: "background:#{enabled ? TINT_BRAND : '#F3F4F6'}") do
          span(class: "flex w-[17px] h-[17px]",
               style: "color:#{enabled ? BRAND : '#9CA3AF'}") do
            render UI::Icon.new(m[:icon], class: "w-full h-full")
          end
        end

        div(class: "flex-1 min-w-0") do
          p(class: "text-[13px] font-semibold text-gray-800") { plain m[:label] }
          p(class: TYPE_CAPTION) { plain m[:desc] }
        end

        label(class: "relative inline-flex items-center cursor-pointer flex-shrink-0") do
          input(type: "checkbox",
                name: "allowed_methods[]",
                value: m[:key],
                class: "sr-only peer",
                **(enabled ? { checked: true } : {}))
          span(class: "w-10 h-6 bg-gray-200 peer-focus:outline-none rounded-full peer " \
                       "peer-checked:after:translate-x-full peer-checked:after:border-white " \
                       "after:content-[''] after:absolute after:top-[2px] after:left-[2px] " \
                       "after:bg-white after:border-gray-300 after:border after:rounded-full " \
                       "after:h-5 after:w-5 after:transition-all",
               style: "#{enabled ? "background:#{BRAND}" : ''}") {}
        end
      end
    end
  end
end
