# frozen_string_literal: true

module Merchants
  class AssignPricingPlanModal < ApplicationComponent
    include UI::Theme

    def initialize(application:, plans: [])
      @app   = application
      @plans = plans
    end

    def view_template
      turbo_frame_tag "modal-frame" do
        div(class: "fixed inset-0 z-50 flex items-center justify-center p-4",
            data: { controller: "modal" }) do
          div(class: "absolute inset-0 bg-black/40 backdrop-blur-[2px]",
              data: { action: "click->modal#close" }) {}

          div(class: "relative #{SURFACE_CARD} w-full max-w-md p-0 overflow-hidden") do
            div(class: "px-6 pt-6 pb-5 border-b border-gray-100") do
              p(class: TYPE_TITLE) { plain "Assign pricing plan" }
              p(class: "#{TYPE_CAPTION} mt-1") do
                plain "Select a plan for #{@app.legal_name || @app.merchant_code}. Takes effect immediately."
              end
            end

            form(action: assign_merchant_pricing_plan_path(@app),
                 method: "post",
                 data: { turbo: false }) do
              input(type: "hidden", name: "_method",            value: "patch")
              input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)

              div(class: "px-6 py-4 flex flex-col gap-2 max-h-[340px] overflow-y-auto") do
                if @plans.empty?
                  p(class: TYPE_CAPTION) { plain "No pricing plans available." }
                else
                  @plans.each { |plan| plan_option(plan) }
                end
              end

              div(class: "px-6 py-4 border-t border-gray-100 flex items-center justify-end gap-3") do
                a(href: merchant_path(@app),
                  class: BTN_SECONDARY,
                  data: { turbo_frame: "_top" }) { plain "Cancel" }
                render UI::Button.new(variant: :primary, type: "submit",
                                      disabled: @plans.empty?) { plain "Assign plan" }
              end
            end
          end
        end
      end
    end

    private

    def plan_option(plan)
      fee_mode_label = plan["fee_mode"] == "invoiced" ? "Invoiced monthly" : "Deducted from settlement"
      monthly        = plan["monthly_fee"].to_i
      monthly_label  = monthly.positive? ? format_money(monthly, currency: plan["currency"]) : "No monthly fee"

      label(for: "plan_#{plan["id"]}",
            class: "flex items-start gap-3 p-3 rounded-xl border border-gray-100 " \
                   "hover:border-gray-200 hover:bg-gray-50 cursor-pointer transition-colors " \
                   "has-[:checked]:border-brand has-[:checked]:bg-brand/5") do
        input(type: "radio", name: "plan_id", value: plan["id"],
              id: "plan_#{plan["id"]}",
              class: "mt-0.5 flex-shrink-0 cursor-pointer accent-[#3D47F5]")
        div do
          p(class: "text-[13px] font-semibold text-gray-800 leading-tight") do
            plain plan["name"] || "Unnamed plan"
            span(class: "#{TYPE_MICRO} text-gray-400 font-normal ml-1.5") { plain "v#{plan["version"]}" } if plan["version"]
          end
          p(class: "#{TYPE_CAPTION} mt-0.5") do
            plain "#{plan["currency"]} · #{fee_mode_label} · #{monthly_label}"
          end
        end
      end
    end
  end
end
