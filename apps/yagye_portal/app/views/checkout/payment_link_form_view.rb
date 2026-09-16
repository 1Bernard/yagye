# frozen_string_literal: true

module Checkout
  class PaymentLinkFormView < ApplicationComponent
    include UI::Theme

    PAYMENT_METHODS = [
      { value: "mobile_money", label: "Mobile Money",   desc: "MTN MoMo, Telecel Cash, AirtelTigo Money" },
      { value: "card",         label: "Card",           desc: "Visa and Mastercard" },
      { value: "bank_transfer",label: "Bank transfer",  desc: "Direct bank-to-bank transfers" }
    ].freeze

    def initialize(errors: [])
      @errors = errors
    end

    def view_template
      render Layout::Shell.new(
        active_nav: :payment_links,
        title: "New payment link",
        breadcrumbs: [
          { label: "Payment Links", href: payment_links_path },
          { label: "New" }
        ]
      ) do
        div(class: "max-w-xl") do
          if @errors.any?
            div(class: ERROR_BANNER) do
              @errors.each { |e| p { plain e } }
            end
          end

          div(class: "#{SURFACE_CARD} p-7") do
            form(action: payment_links_path, method: "post", class: "space-y-6") do
              input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)

              # Description
              field_block("Description") do
                input(
                  type: "text", name: "description",
                  placeholder: "e.g. Product deposit, event ticket",
                  class: INPUT_FIELD, required: true
                )
              end

              # Kind
              field_block("Payment type") do
                div(class: "flex gap-3") do
                  kind_option("fixed_amount",       "Fixed amount", "Customer pays a set amount", checked: true)
                  kind_option("customer_specified",  "Open amount",  "Customer enters the amount")
                end
              end

              # Amount — shown for fixed_amount only
              div(id: "amount-row") do
                field_block("Amount (GHS)") do
                  input(
                    type: "number", name: "amount", step: "0.01", min: "0.01",
                    placeholder: "50.00", id: "amount-input",
                    class: INPUT_FIELD
                  )
                end
              end

              # Currency
              field_block("Currency") do
                select(name: "currency", class: SELECT_FIELD) do
                  option(value: "GHS", selected: "selected") { plain "GHS — Ghana Cedi" }
                  option(value: "USD") { plain "USD — US Dollar" }
                  option(value: "NGN") { plain "NGN — Nigerian Naira" }
                end
              end

              div(class: "border-t border-gray-100")

              # Allowed payment methods
              field_block("Accepted payment methods") do
                p(class: "#{TYPE_CAPTION} text-gray-400 mb-3") do
                  plain "Select which methods customers can use on the checkout page. Choose at least one."
                end
                div(class: "flex flex-col gap-2") do
                  PAYMENT_METHODS.each do |m|
                    method_option(m[:value], m[:label], m[:desc])
                  end
                end
              end

              div(class: "border-t border-gray-100")

              # Collect from customer
              field_block("Collect from customer") do
                div(class: "flex flex-col gap-2") do
                  checkbox_opt("collect_email", "Email address")
                  checkbox_opt("collect_phone", "Phone number")
                  checkbox_opt("collect_name",  "Full name")
                end
              end

              div(class: "border-t border-gray-100")

              # Reusable + max uses
              field_block("Usage") do
                div(class: "flex flex-col gap-3") do
                  div(class: "flex items-center gap-2") do
                    input(type: "checkbox", name: "reusable", value: "1", id: "reusable",
                          class: CHECKBOX_INPUT, checked: true)
                    label(for: "reusable", class: TYPE_BODY) { plain "Allow multiple uses" }
                  end

                  div(id: "max-uses-row", class: "pl-6") do
                    label(class: "block #{TYPE_CAPTION} mb-1.5 font-medium text-gray-700") do
                      plain "Maximum uses"
                    end
                    input(
                      type: "number", name: "max_uses", min: "1", id: "max-uses-input",
                      placeholder: "Leave blank for unlimited",
                      class: INPUT_FIELD
                    )
                    p(class: "#{TYPE_MICRO} text-gray-400 mt-1") do
                      plain "e.g. 1 = single-use, 100 = limited run. Blank = no limit."
                    end
                  end
                end
              end

              # Expiry
              field_block("Link expiry") do
                p(class: "#{TYPE_CAPTION} text-gray-400 mb-2") do
                  plain "Optional. The link stops accepting payments after this date."
                end
                input(
                  type: "datetime-local", name: "expires_at",
                  class: INPUT_FIELD
                )
              end

              div(class: "pt-1") do
                render UI::Button.new(variant: :primary, type: "submit") { plain "Create & configure layout" }
              end
            end
          end
        end

        script do
          raw safe(<<~JS)
            // Toggle amount row based on kind
            const amountRow   = document.getElementById('amount-row');
            const amountInput = document.getElementById('amount-input');
            document.querySelectorAll('input[name="kind"]').forEach(r => {
              r.addEventListener('change', () => {
                const fixed = r.value === 'fixed_amount';
                amountRow.style.display = fixed ? '' : 'none';
                amountInput.required    = fixed;
              });
            });

            // Toggle max-uses row based on reusable checkbox
            const reusableChk  = document.getElementById('reusable');
            const maxUsesRow   = document.getElementById('max-uses-row');
            const maxUsesInput = document.getElementById('max-uses-input');
            function syncMaxUses() {
              const show = reusableChk.checked;
              maxUsesRow.style.display = show ? '' : 'none';
              if (!show) maxUsesInput.value = '';
            }
            reusableChk.addEventListener('change', syncMaxUses);
            syncMaxUses();
          JS
        end
      end
    end

    private

    def field_block(label_text, &block)
      div do
        label(class: "block #{TYPE_CAPTION} mb-2 font-medium text-gray-700") { plain label_text }
        yield
      end
    end

    def kind_option(value, label, description, checked: false)
      div(class: "flex-1 cursor-pointer") do
        input(type: "radio", name: "kind", value: value, id: "kind_#{value}",
              class: "peer sr-only", checked: checked ? true : nil)
        label(
          for: "kind_#{value}",
          class: "block cursor-pointer border-2 border-gray-200 rounded-xl p-4 " \
                 "peer-checked:border-[#3D47F5] peer-checked:bg-blue-50/30 transition-colors"
        ) do
          p(class: "text-[13px] font-semibold text-gray-800") { plain label }
          p(class: "text-[12px] text-gray-500 mt-0.5") { plain description }
        end
      end
    end

    def method_option(value, label_text, description)
      div(class: "flex items-start gap-2") do
        input(type: "checkbox", name: "allowed_methods[]", value: value,
              id: "method_#{value}", class: CHECKBOX_INPUT, checked: true)
        div do
          label(for: "method_#{value}", class: "block text-[13px] font-medium text-gray-800 cursor-pointer") do
            plain label_text
          end
          p(class: "#{TYPE_MICRO} text-gray-400 mt-[1px]") { plain description }
        end
      end
    end

    def checkbox_opt(name, label_text)
      div(class: "flex items-center gap-2") do
        input(type: "checkbox", name: name, value: "1", id: name, class: CHECKBOX_INPUT)
        label(for: name, class: TYPE_BODY) { plain label_text }
      end
    end
  end
end
