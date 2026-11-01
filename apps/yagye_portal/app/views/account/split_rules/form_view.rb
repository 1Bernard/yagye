# frozen_string_literal: true

module Account
  module SplitRules
    class FormView < ApplicationComponent
      include UI::Theme

      def initialize(mode: "live", errors: [])
        @mode   = mode
        @errors = errors
      end

      def view_template
        render Layout::Shell.new(
          active_nav:  :split_rules,
          title:       "New Split Rule",
          breadcrumbs: [
            { label: "Settings",    href: settings_path },
            { label: "Split Rules", href: split_rules_path },
            { label: "New" }
          ]
        ) do
          render UI::ErrorBanner.new(errors: @errors) if @errors.any?

          div(class: "max-w-2xl") do
            render UI::Card.new do |c|
              c.header("Split rule", icon: :share)
              c.body do
                form(action: split_rules_path, method: "post",
                     data: { controller: "split-legs" }) do
                  input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)

                  div(class: "flex flex-col gap-5") do
                    name_field
                    legs_section
                    hint_box
                    form_actions
                  end
                end
              end
            end
          end
        end
      end

      private

      def name_field
        div(class: "flex flex-col gap-1.5") do
          label(class: TEXT_LABEL, for: "name") { plain "Rule name" }
          input(type: "text", name: "name", id: "name", required: true,
                placeholder: "e.g. Platform fee split",
                class: TEXT_FIELD)
          p(class: FORM_HINT) { plain "Internal label. Not shown to customers." }
        end
      end

      def legs_section
        div(class: "flex flex-col gap-3") do
          div(class: "flex items-center justify-between") do
            p(class: "text-[13px] font-semibold text-gray-800") { plain "Legs" }
            button(type: "button",
                   class: "text-[12px] font-medium text-[#3D47F5] hover:underline",
                   data: { action: "click->split-legs#addLeg" }) do
              plain "+ Add leg"
            end
          end

          p(class: FORM_HINT) do
            plain "Each leg routes a share of the payment to a recipient merchant account. "
            plain "For percentage splits, legs must total 100%."
          end

          div(data: { split_legs_target: "container" }, class: "flex flex-col gap-3") do
            leg_row(0)
          end

          # Template for JS cloning
          template(data: { split_legs_target: "template" }) do
            leg_row("__IDX__")
          end
        end
      end

      def leg_row(idx)
        div(class: "bg-gray-50 rounded-xl px-4 py-4 flex flex-col gap-3 relative",
            data: { split_legs_target: "leg" }) do
          button(type: "button",
                 class: "absolute top-3 right-3 text-gray-300 hover:text-red-400 transition-colors",
                 data: { action: "click->split-legs#removeLeg" }) do
            render UI::Icon.new(:x, class: "w-3.5 h-3.5")
          end

          div(class: "grid grid-cols-2 gap-3") do
            div(class: "flex flex-col gap-1.5") do
              label(class: TEXT_LABEL) { plain "Recipient merchant code" }
              input(type: "text",
                    name: "legs[#{idx}][recipient_merchant_code]",
                    placeholder: "e.g. MCH_abc123",
                    class: TEXT_FIELD)
            end
            div(class: "flex flex-col gap-1.5") do
              label(class: TEXT_LABEL) { plain "Type" }
              select(name: "legs[#{idx}][split_type]",
                     class: "#{TEXT_FIELD} cursor-pointer",
                     data: { action: "change->split-legs#typeChanged" }) do
                option(value: "percentage") { plain "Percentage (%)" }
                option(value: "flat")       { plain "Flat amount" }
              end
            end
          end

          div(class: "flex flex-col gap-1.5") do
            label(class: TEXT_LABEL) { plain "Value" }
            div(class: "relative flex items-center") do
              input(type: "number", step: "0.01", min: "0.01",
                    name: "legs[#{idx}][value]",
                    placeholder: "e.g. 10.00",
                    class: "#{TEXT_FIELD} pr-14")
              span(class: "absolute right-3 text-[12px] text-gray-400",
                   data: { split_legs_target: "unit_#{idx}" }) do
                plain "%"
              end
            end
          end
        end
      end

      def hint_box
        div(class: "flex items-start gap-3 p-3 rounded-xl bg-blue-50 border border-blue-100") do
          span(class: "flex w-[14px] h-[14px] flex-shrink-0 mt-px text-blue-500") do
            render UI::Icon.new(:info, class: "w-full h-full")
          end
          p(class: "text-[12px] text-blue-700") do
            plain "Split rules run automatically after a payment succeeds. "
            plain "The payment's split_rule_id must be set at checkout time to activate the rule."
          end
        end
      end

      def form_actions
        div(class: "flex items-center gap-3 pt-2 border-t border-gray-100") do
          render UI::Button.new(variant: :primary, type: "submit") { plain "Create split rule" }
          a(href: split_rules_path, class: "text-[12.5px] font-medium text-gray-500 hover:text-gray-800") do
            plain "Cancel"
          end
        end
      end
    end
  end
end
