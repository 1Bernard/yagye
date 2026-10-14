# frozen_string_literal: true

module Account
  module Pricing
    class IndexView < ApplicationComponent
      include UI::Theme

      def initialize(plan:)
        @plan = plan
      end

      def view_template
        render Layout::Shell.new(
          active_nav:  :settings_pricing,
          title:       "Pricing & Fees",
          breadcrumbs: [
            { label: "Pricing & Fees" }
          ]
        ) do
          render UI::PageHeader.new(
            title:    "Pricing & Fees",
            subtitle: "Your current rate card and how platform fees are calculated."
          )

          if @plan.nil?
            no_plan_state
          else
            plan_content
          end
        end
      end

      private

      # ── No plan assigned ──────────────────────────────────────────────────────

      def no_plan_state
        div(class: "#{SURFACE_CARD} px-8 py-14 flex flex-col items-center text-center gap-3") do
          div(class: "w-12 h-12 rounded-2xl flex items-center justify-center mb-1",
              style: "background:#{TINT_BRAND}") do
            span(class: "flex w-[22px] h-[22px]", style: "color:#{BRAND}") do
              render UI::Icon.new(:tag, class: "w-full h-full")
            end
          end
          p(class: TYPE_TITLE) { plain "No pricing plan assigned yet" }
          p(class: "#{TYPE_CAPTION} max-w-sm") do
            plain "Your account hasn't been assigned a pricing plan. "
            plain "This will be set during onboarding. Contact support if you think this is an error."
          end
        end
      end

      # ── Plan summary + rules ──────────────────────────────────────────────────

      def plan_content
        div(class: "flex flex-col gap-5") do
          plan_hero
          rules_card
          fee_mode_explainer
          invoices_link if @plan["fee_mode"] == "invoiced"
        end
      end

      def plan_hero
        mode      = @plan["fee_mode"] || "deducted"
        monthly   = @plan["monthly_fee"].to_i
        cur       = @plan["currency"] || "GHS"
        eff_from  = @plan["effective_from"]

        mode_label = mode == "invoiced" ? "Invoiced (billed monthly)" : "Deducted from settlement"
        mode_status = mode == "invoiced" ? STATUS_INFO : STATUS_SUCCESS

        div(class: "#{SURFACE_CARD} px-8 py-7") do
          div(class: "flex items-start justify-between mb-5") do
            div do
              p(class: "#{TYPE_CAPTION} mb-1") { plain "Pricing plan" }
              p(class: TYPE_HEADING) { plain @plan["name"] || "Standard" }
              p(class: "#{TYPE_CAPTION} mt-0.5") { plain "v#{@plan["version"]}" } if @plan["version"]
            end
            span(class: "#{BADGE} #{mode_status}") { plain mode_label }
          end
          div(class: "grid grid-cols-3 gap-[1px] bg-gray-100 rounded-xl overflow-hidden") do
            meta_cell("Currency",      cur)
            meta_cell("Monthly fee",   monthly.positive? ? format_money(monthly, currency: cur) : "None")
            meta_cell("Active since",  eff_from ? (fmt_date(Date.parse(eff_from.to_s)) rescue "—") : "—")
          end
        end
      end

      def rules_card
        render UI::Card.new do |card|
          card.header("Rate card")
          card.body(padding: false) do
            render UI::PricingRateCard.new(plan: @plan)
          end
        end
      end

      def fee_mode_explainer
        mode = @plan["fee_mode"] || "deducted"

        render UI::Notice.new(title: "How your fees work", variant: :info, size: :lg) do
          if mode == "deducted"
            ul(class: "#{TYPE_CAPTION} mt-[3px] space-y-1 list-disc list-inside") do
              li { plain "Fees are automatically deducted from each settlement batch." }
              li { plain "Your settlement net amount = gross volume − platform fees." }
              li { plain "Fee and net amount are shown on each payment and each settlement batch." }
              li { plain "No separate invoice — everything is visible in your dashboard." }
            end
          else
            ul(class: "#{TYPE_CAPTION} mt-[3px] space-y-1 list-disc list-inside") do
              li { plain "You receive gross settlement — no fees are taken from each batch." }
              li { plain "Fees are consolidated into a monthly platform fee invoice." }
              li { plain "Invoices are billed at the start of each month for the prior period." }
            end
          end
        end
      end

      def invoices_link
        div(class: "flex items-center justify-between #{SURFACE_CARD} px-6 py-4") do
          div do
            p(class: TYPE_BODY_MD) { plain "Platform fee invoices" }
            p(class: "#{TYPE_CAPTION} mt-0.5") { plain "View your monthly fee invoices and collection history." }
          end
          render UI::Button.new(variant: :secondary, href: settings_fee_invoices_path) do
            plain "View invoices"
            span(class: "flex w-[12px] h-[12px]") { render UI::Icon.new(:arrow_right, class: "w-full h-full") }
          end
        end
      end
    end
  end
end
