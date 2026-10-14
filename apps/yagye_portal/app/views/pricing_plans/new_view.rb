# frozen_string_literal: true

module PricingPlans
  class NewView < ApplicationComponent
    include UI::Theme

    def initialize(errors: {}, params: {})
      @errors = errors
      @params = params
    end

    def view_template
      render Layout::Shell.new(
        active_nav:  :pricing_plans,
        title:       "New Pricing Plan",
        breadcrumbs: [
          { label: "Pricing Plans", href: pricing_plans_path },
          { label: "New plan" }
        ]
      ) do
        render UI::PageHeader.new(
          title:    "New pricing plan",
          subtitle: "Define a plan name, currency and fee mode. Add pricing rules after creation."
        )

        div(class: "max-w-xl mt-5") do
          render UI::Card.new do |c|
            c.body do
              form(action: pricing_plans_path, method: "post") do
                input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)

                div(class: "flex flex-col gap-5") do
                  field_group("Plan name", :name, placeholder: "e.g. Standard GHS") do
                    error_for(:name)
                  end

                  div(class: "grid grid-cols-2 gap-4") do
                    field_group("Version", :version, placeholder: "1", type: "number") do
                      error_for(:version)
                    end
                    div do
                      label(class: "block #{TYPE_MICRO} text-gray-500 font-medium mb-1.5") { plain "Currency" }
                      select(name: "currency", class: select_cls) do
                        option(value: "GHS", selected: true) { plain "GHS — Ghanaian Cedi" }
                      end
                      error_for(:currency)
                    end
                  end

                  div do
                    label(class: "block #{TYPE_MICRO} text-gray-500 font-medium mb-1.5") { plain "Fee mode" }
                    select(name: "fee_mode", class: select_cls) do
                      option(value: "deducted", selected: @params[:fee_mode] != "invoiced") { plain "Deducted from settlement" }
                      option(value: "invoiced",  selected: @params[:fee_mode] == "invoiced") { plain "Invoiced monthly" }
                    end
                    error_for(:fee_mode)
                  end

                  field_group("Monthly fee (pesewas, 0 = none)", :monthly_fee,
                              placeholder: "0", type: "number", value: @params[:monthly_fee]) do
                    p(class: "#{TYPE_MICRO} text-gray-400 mt-1") { plain "Enter in minor units (pesewas). 100 = GHS 1.00" }
                    error_for(:monthly_fee)
                  end

                  field_group("Effective from", :effective_from, type: "date",
                              value: @params[:effective_from]) do
                    error_for(:effective_from)
                  end

                  div(class: "flex items-center justify-end gap-3 pt-2") do
                    a(href: pricing_plans_path, class: BTN_SECONDARY) { plain "Cancel" }
                    render UI::Button.new(variant: :primary, type: "submit") { plain "Create plan" }
                  end
                end
              end
            end
          end
        end
      end
    end

    private

    def field_group(label_text, field, placeholder: nil, type: "text", value: nil, &block)
      div do
        label(class: "block #{TYPE_MICRO} text-gray-500 font-medium mb-1.5") { plain label_text }
        input(
          type:        type,
          name:        field,
          value:       value || @params[field],
          placeholder: placeholder,
          class:       input_cls
        )
        yield if block_given?
      end
    end

    def input_cls
      "w-full border border-gray-200 rounded-xl px-3.5 py-2.5 text-[13px] text-gray-800 " \
        "bg-white focus:outline-none focus:ring-2 focus:ring-indigo-500/20 focus:border-indigo-400"
    end

    def select_cls = input_cls

    def error_for(field)
      msgs = @errors[field.to_s] || @errors[field.to_sym] || []
      return if msgs.empty?

      p(class: "text-[11.5px] text-red-600 mt-1") { plain msgs.first }
    end
  end
end
