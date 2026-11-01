# frozen_string_literal: true

module PricingPlans
  class NewDrawerView < ApplicationComponent
    include UI::Theme

    def initialize(errors: {}, params: {})
      @errors = errors
      @params = params
    end

    def view_template
      turbo_frame_tag "drawer-frame", class: "flex flex-col min-h-full w-full" do
        div(class: "#{DRAWER_HEAD} flex-shrink-0") do
          div(class: "flex items-center gap-3 min-w-0") do
            div(class: "w-8 h-8 rounded-lg flex items-center justify-center flex-shrink-0",
                style: "background:#{TINT_BRAND}") do
              span(class: "flex w-[14px] h-[14px]", style: "color:#{BRAND}") do
                render UI::Icon.new(:tag, class: "w-full h-full")
              end
            end
            div do
              p(class: TYPE_MICRO) { plain "Pricing Plans" }
              p(class: "text-[14px] font-semibold", style: "color:var(--ink)") { plain "New pricing plan" }
            end
          end
          button(type: "button", class: XBTN,
                 data: { action: "click->drawer#close" },
                 aria: { label: "Close" }) do
            render UI::Icon.new(:x, class: ICON_SM)
          end
        end

        form(action: pricing_plans_path, method: "post", class: "flex flex-col flex-1") do
          input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)

          div(class: "p-6 flex flex-col gap-5 flex-1") do
            p(class: TYPE_CAPTION) do
              plain "Define a plan name, currency and fee mode. Add pricing rules after creation."
            end

            field_group("Plan name", :name, placeholder: "e.g. Standard GHS") do
              error_for(:name)
            end

            div(class: "grid grid-cols-2 gap-4") do
              field_group("Version", :version, placeholder: "1", type: "number") do
                error_for(:version)
              end
              div do
                label(class: "block #{TEXT_LABEL} mb-1.5") { plain "Currency" }
                select(name: "currency", class: SELECT_FIELD) do
                  option(value: "GHS", selected: true) { plain "GHS — Ghanaian Cedi" }
                end
                error_for(:currency)
              end
            end

            div do
              label(class: "block #{TEXT_LABEL} mb-1.5") { plain "Fee mode" }
              select(name: "fee_mode", class: SELECT_FIELD) do
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
          end

          div(class: "sticky bottom-0 flex items-center justify-end gap-3 px-6 py-5 " \
                     "border-t border-gray-100 bg-white flex-shrink-0") do
            button(type: "button",
                   class: BTN_SECONDARY,
                   data: { action: "click->drawer#close" }) { plain "Cancel" }
            render UI::Button.new(variant: :primary, type: "submit") { plain "Create plan" }
          end
        end
      end
    end

    private

    def field_group(label_text, field, placeholder: nil, type: "text", value: nil, &block)
      div do
        label(class: "block #{TEXT_LABEL} mb-1.5") { plain label_text }
        input(
          type:        type,
          name:        field,
          value:       value || @params[field],
          placeholder: placeholder,
          class:       INPUT_FIELD
        )
        yield if block_given?
      end
    end

    def error_for(field)
      msgs = @errors[field.to_s] || @errors[field.to_sym] || []
      return if msgs.empty?

      p(class: "text-[11.5px] text-red-600 mt-1") { plain msgs.first }
    end
  end
end
