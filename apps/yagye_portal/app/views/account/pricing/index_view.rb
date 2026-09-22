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
        div(class: "bg-white border border-gray-100 rounded-2xl px-8 py-14 flex flex-col items-center text-center gap-3") do
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
        mode_css   = mode == "invoiced" ? "bg-purple-50 text-purple-700" : "bg-green-50 text-green-700"

        div(class: "bg-white border border-gray-100 rounded-2xl px-8 py-7") do
          div(class: "flex items-start justify-between mb-5") do
            div do
              p(class: "#{TYPE_CAPTION} mb-1") { plain "Pricing plan" }
              p(class: TYPE_HEADING) { plain @plan["name"] || "Standard" }
              p(class: "#{TYPE_CAPTION} mt-0.5") { plain "v#{@plan["version"]}" } if @plan["version"]
            end
            span(class: "inline-flex items-center px-2.5 py-1 rounded-full text-[11.5px] font-semibold #{mode_css}") do
              plain mode_label
            end
          end
          div(class: "grid grid-cols-3 gap-[1px] bg-gray-100 rounded-xl overflow-hidden") do
            meta_cell("Currency",      cur)
            meta_cell("Monthly fee",   monthly.positive? ? format_money(monthly, currency: cur) : "None")
            meta_cell("Active since",  eff_from ? Date.parse(eff_from.to_s).strftime("%d %b %Y") : "—")
          end
        end
      end

      def rules_card
        rules = @plan["rules"] || []

        render UI::Card.new do |card|
          card.header("Rate card")
          card.body(padding: false) do
            if rules.empty?
              div(class: "px-5 py-10 text-center") do
                p(class: TYPE_CAPTION) { plain "No pricing rules defined for this plan." }
              end
            else
              div(class: "overflow-x-auto") do
                table(class: "w-full text-left") do
                  thead do
                    tr(class: "border-b border-gray-100") do
                      th(class: "px-5 py-3 #{TYPE_MICRO} text-gray-400 font-semibold uppercase tracking-wide") { plain "Method" }
                      th(class: "px-5 py-3 #{TYPE_MICRO} text-gray-400 font-semibold uppercase tracking-wide") { plain "Provider" }
                      th(class: "px-5 py-3 #{TYPE_MICRO} text-gray-400 font-semibold uppercase tracking-wide text-right") { plain "Rate" }
                      th(class: "px-5 py-3 #{TYPE_MICRO} text-gray-400 font-semibold uppercase tracking-wide text-right") { plain "Fixed" }
                      th(class: "px-5 py-3 #{TYPE_MICRO} text-gray-400 font-semibold uppercase tracking-wide text-right") { plain "Min" }
                      th(class: "px-5 py-3 #{TYPE_MICRO} text-gray-400 font-semibold uppercase tracking-wide text-right") { plain "Max" }
                      th(class: "px-5 py-3 #{TYPE_MICRO} text-gray-400 font-semibold uppercase tracking-wide") { plain "Amount band" }
                    end
                  end
                  tbody(class: "divide-y divide-gray-50") do
                    rules.each { |r| rule_row(r) }
                  end
                end
              end
            end
          end
        end
      end

      def rule_row(r)
        cur   = @plan["currency"] || "GHS"
        pct   = r["percentage_bps"].to_i
        fixed = r["fixed_amount"].to_i
        min_f = r["minimum_fee"]
        max_f = r["maximum_fee"]

        pct_label   = pct.positive?   ? "#{sprintf('%.4f', pct / 100.0).sub(/0+$/, '').sub(/\.$/, '.0')}%" : "—"
        fixed_label = fixed.positive? ? format_money(fixed, currency: cur) : "—"
        min_label   = min_f ? format_money(min_f.to_i, currency: cur) : "—"
        max_label   = max_f ? format_money(max_f.to_i, currency: cur) : "—"

        amount_min = r["amount_min"]
        amount_max = r["amount_max"]
        band_label = if amount_min || amount_max
                       from_s = amount_min ? format_money(amount_min.to_i, currency: cur) : "0"
                       to_s   = amount_max ? format_money(amount_max.to_i, currency: cur) : "∞"
                       "#{from_s} – #{to_s}"
                     else
                       "All amounts"
                     end

        tr(class: "hover:bg-gray-50 transition-colors") do
          td(class: "px-5 py-3 #{TYPE_BODY_MD}") do
            plain(r["method"]&.humanize || "Any method")
          end
          td(class: "px-5 py-3 #{TYPE_BODY_MD} text-gray-500") do
            plain(r["provider_code"]&.upcase || "—")
          end
          td(class: "px-5 py-3 #{TYPE_BODY_MD} text-right font-semibold tabular-nums") { plain pct_label }
          td(class: "px-5 py-3 #{TYPE_BODY_MD} text-right tabular-nums") { plain fixed_label }
          td(class: "px-5 py-3 #{TYPE_CAPTION} text-right tabular-nums") { plain min_label }
          td(class: "px-5 py-3 #{TYPE_CAPTION} text-right tabular-nums") { plain max_label }
          td(class: "px-5 py-3 #{TYPE_CAPTION} text-gray-500") { plain band_label }
        end
      end

      def fee_mode_explainer
        mode = @plan["fee_mode"] || "deducted"

        div(class: "bg-blue-50 border border-blue-100 rounded-2xl px-6 py-5") do
          p(class: "text-[13px] font-semibold text-blue-800 mb-1.5") { plain "How your fees work" }
          if mode == "deducted"
            ul(class: "#{TYPE_CAPTION} text-blue-700 space-y-1 list-disc list-inside") do
              li { plain "Fees are automatically deducted from each settlement batch." }
              li { plain "Your settlement net amount = gross volume − platform fees." }
              li { plain "No separate invoice — everything is visible on each settlement batch." }
            end
          else
            ul(class: "#{TYPE_CAPTION} text-blue-700 space-y-1 list-disc list-inside") do
              li { plain "You receive gross settlement — no fees are taken from each batch." }
              li { plain "Fees are consolidated into a monthly platform fee invoice." }
              li { plain "Invoices are billed at the start of each month for the prior period." }
            end
          end
        end
      end

      def invoices_link
        div(class: "flex items-center justify-between bg-white border border-gray-100 rounded-2xl px-6 py-4") do
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
