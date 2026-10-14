# frozen_string_literal: true

module Settings
  class CheckoutPanel < ApplicationComponent
    include UI::Theme

    METHODS = [
      {
        key:         "mobile_money",
        label:       "Mobile Money",
        description: "MTN MoMo, Telecel Cash, AirtelTigo Money",
        icon:        :smartphone
      },
      {
        key:         "card",
        label:       "Card",
        description: "Visa, Mastercard and major card networks",
        icon:        :credit_card
      },
      {
        key:         "bank_transfer",
        label:       "Bank Transfer",
        description: "Direct bank account payments",
        icon:        :bank
      }
    ].freeze

    def initialize(allowed_methods: %w[mobile_money card bank_transfer])
      @allowed_methods = Array(allowed_methods)
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
            plain "Control which payment methods appear on your checkout pages and payment links."
          end
        end

        form(action: settings_checkout_path, method: "post") do
          input(type: "hidden", name: "_method",            value: "patch")
          input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)

          div(class: "divide-y divide-gray-50") do
            METHODS.each { |m| method_row(m) }
          end

          div(class: "px-6 py-4 border-t border-gray-100 flex items-center justify-between") do
            p(class: TYPE_CAPTION) do
              plain "At least one method must remain enabled."
            end
            render UI::Button.new(variant: :primary, type: "submit") { plain "Save changes" }
          end
        end
      end
    end

    def method_row(method)
      enabled = @allowed_methods.include?(method[:key])

      div(class: "px-6 py-4 flex items-center gap-4") do
        div(class: "w-10 h-10 rounded-xl flex items-center justify-center flex-shrink-0",
            style: "background:#{enabled ? TINT_BRAND : '#F3F4F6'}") do
          span(class: "flex w-[18px] h-[18px]",
               style: "color:#{enabled ? BRAND : '#9CA3AF'}") do
            render UI::Icon.new(method[:icon], class: "w-full h-full")
          end
        end

        div(class: "flex-1 min-w-0") do
          p(class: "text-[13px] font-semibold text-gray-800") { plain method[:label] }
          p(class: "#{TYPE_CAPTION} mt-[2px]") { plain method[:description] }
        end

        label(class: "relative inline-flex items-center cursor-pointer flex-shrink-0") do
          input(
            type:    "checkbox",
            name:    "allowed_methods[]",
            value:   method[:key],
            checked: enabled,
            class:   "sr-only peer",
            id:      "method_#{method[:key]}"
          )
          div(
            class: "w-10 h-6 bg-gray-200 peer-focus:outline-none rounded-full peer " \
                   "peer-checked:after:translate-x-full rtl:peer-checked:after:-translate-x-full " \
                   "peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] " \
                   "after:start-[2px] after:bg-white after:border-gray-300 after:border " \
                   "after:rounded-full after:h-5 after:w-5 after:transition-all",
            style: "#{enabled ? "background-color:#{BRAND}" : ''}"
          )
        end
      end
    end
  end
end
