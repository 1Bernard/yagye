# frozen_string_literal: true

module Ops
  module PricingPlans
    class IndexView < ApplicationComponent
      include UI::Theme

      def initialize(plans: [])
        @plans = plans
      end

      def view_template
        render Layout::Shell.new(
          active_nav:  :pricing_plans,
          title:       "Pricing Plans",
          breadcrumbs: [{ label: "Pricing Plans" }]
        ) do
          render UI::PageHeader.new(
            title:    "Pricing Plans",
            subtitle: "Global rate plans that can be assigned to merchants."
          ) do
            render UI::Button.new(variant: :primary, href: new_pricing_plan_path) do
              render UI::Icon.new(:plus, class: "w-[14px] h-[14px]")
              plain "New plan"
            end
          end

          if @plans.empty?
            div(class: "#{SURFACE_CARD} px-8 py-14 flex flex-col items-center text-center gap-3 mt-4") do
              div(class: "w-12 h-12 rounded-2xl flex items-center justify-center mb-1",
                  style: "background:#{TINT_BRAND}") do
                span(class: "flex w-[22px] h-[22px]", style: "color:#{BRAND}") do
                  render UI::Icon.new(:tag, class: "w-full h-full")
                end
              end
              p(class: TYPE_TITLE) { plain "No pricing plans yet" }
              p(class: "#{TYPE_CAPTION} max-w-sm") { plain "Create a plan to define the rates merchants will be charged." }
              render UI::Button.new(variant: :primary, href: new_pricing_plan_path) { plain "Create first plan" }
            end
          else
            div(class: "#{SURFACE_CARD} overflow-hidden mt-4") do
              table(class: "w-full text-left") do
                thead do
                  tr(class: "border-b border-gray-100") do
                    th(class: "px-5 py-3 #{TYPE_MICRO} text-gray-400 font-semibold uppercase tracking-wide") { plain "Plan" }
                    th(class: "px-5 py-3 #{TYPE_MICRO} text-gray-400 font-semibold uppercase tracking-wide") { plain "Currency" }
                    th(class: "px-5 py-3 #{TYPE_MICRO} text-gray-400 font-semibold uppercase tracking-wide") { plain "Fee mode" }
                    th(class: "px-5 py-3 #{TYPE_MICRO} text-gray-400 font-semibold uppercase tracking-wide") { plain "Monthly fee" }
                    th(class: "px-5 py-3 #{TYPE_MICRO} text-gray-400 font-semibold uppercase tracking-wide") { plain "Active from" }
                    th(class: "px-5 py-3") {}
                  end
                end
                tbody(class: "divide-y divide-gray-50") do
                  @plans.each { |p| plan_row(p) }
                end
              end
            end
          end
        end
      end

      private

      def plan_row(plan)
        cur     = plan["currency"] || "GHS"
        monthly = plan["monthly_fee"].to_i
        mode    = plan["fee_mode"] == "invoiced" ? "Invoiced" : "Deducted"
        eff     = begin
          fmt_date(Date.parse(plan["effective_from"].to_s)) if plan["effective_from"]
        rescue
          "—"
        end

        tr(class: "hover:bg-gray-50 transition-colors") do
          td(class: "px-5 py-3.5") do
            p(class: TYPE_BODY_MD) { plain plan["name"] || "—" }
            p(class: TYPE_CAPTION) { plain "v#{plan["version"]}" } if plan["version"]
          end
          td(class: "px-5 py-3.5 #{TYPE_CAPTION}") { plain cur }
          td(class: "px-5 py-3.5") do
            span(class: "#{BADGE} #{mode == 'Invoiced' ? STATUS_INFO : STATUS_SUCCESS}") { plain mode }
          end
          td(class: "px-5 py-3.5 #{TYPE_CAPTION} tabular-nums") do
            plain monthly.positive? ? format_money(monthly, currency: cur) : "None"
          end
          td(class: "px-5 py-3.5 #{TYPE_CAPTION}") { plain eff || "—" }
          td(class: "px-5 py-3.5 text-right") do
            a(href: pricing_plan_path(plan["id"]),
              class: "#{TYPE_CAPTION} font-medium text-indigo-600 hover:underline") { plain "View" }
          end
        end
      end
    end
  end
end
