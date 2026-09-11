# frozen_string_literal: true

module Checkout
  class PaymentLinkFormView < ApplicationComponent
    include UI::Theme

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
            form(action: payment_links_path, method: "post", class: "space-y-5") do
              input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)

              # Description
              div do
                label(class: "block #{TYPE_CAPTION} mb-1.5 font-medium text-gray-700") { plain "Description" }
                input(
                  type: "text", name: "description",
                  placeholder: "e.g. Product deposit, event ticket",
                  class: INPUT_FIELD, required: true
                )
              end

              # Kind
              div do
                label(class: "block #{TYPE_CAPTION} mb-2 font-medium text-gray-700") { plain "Payment type" }
                div(class: "flex gap-3") do
                  kind_option("fixed_amount", "Fixed amount", "Customer pays a set amount", checked: true)
                  kind_option("customer_specified", "Open amount", "Customer enters the amount")
                end
              end

              # Amount (shown for fixed_amount)
              div(id: "amount-row") do
                label(class: "block #{TYPE_CAPTION} mb-1.5 font-medium text-gray-700") { plain "Amount (GHS)" }
                input(
                  type: "number", name: "amount", step: "0.01", min: "0.01",
                  placeholder: "50.00", required: true, id: "amount-input",
                  class: INPUT_FIELD
                )
              end

              # Currency
              div do
                label(class: "block #{TYPE_CAPTION} mb-1.5 font-medium text-gray-700") { plain "Currency" }
                select(name: "currency", class: SELECT_FIELD) do
                  option(value: "GHS", selected: "selected") { plain "GHS — Ghana Cedi" }
                  option(value: "USD") { plain "USD — US Dollar" }
                  option(value: "NGN") { plain "NGN — Nigerian Naira" }
                end
              end

              # Collection checkboxes
              div do
                label(class: "block #{TYPE_CAPTION} mb-2.5 font-medium text-gray-700") { plain "Collect from customer" }
                div(class: "flex flex-col gap-2") do
                  checkbox_opt("collect_email", "Email address")
                  checkbox_opt("collect_phone", "Phone number")
                  checkbox_opt("collect_name", "Full name")
                end
              end

              # Reusable
              div(class: "flex items-center gap-2") do
                input(type: "checkbox", name: "reusable", value: "1", id: "reusable",
                      class: CHECKBOX_INPUT, checked: true)
                label(for: "reusable", class: TYPE_BODY) { plain "Allow multiple uses" }
              end

              # Submit
              div(class: "pt-1") do
                render UI::Button.new(variant: :primary, type: "submit") { plain "Create & configure layout" }
              end
            end
          end
        end

        # Toggle amount row based on kind selection
        script do
          raw safe(<<~JS)
            const amountRow   = document.getElementById('amount-row');
            const amountInput = document.getElementById('amount-input');
            document.querySelectorAll('input[name="kind"]').forEach(r => {
              r.addEventListener('change', () => {
                const fixed = r.value === 'fixed_amount';
                amountRow.style.display  = fixed ? '' : 'none';
                amountInput.required     = fixed;
              });
            });
          JS
        end
      end
    end

    private

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

    def checkbox_opt(name, label_text)
      div(class: "flex items-center gap-2") do
        input(type: "checkbox", name: name, value: "1", id: name, class: CHECKBOX_INPUT)
        label(for: name, class: TYPE_BODY) { plain label_text }
      end
    end
  end
end
