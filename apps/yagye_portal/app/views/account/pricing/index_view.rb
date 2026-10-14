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
        mode_css   = mode == "invoiced" ? "bg-purple-50 text-purple-700" : "bg-green-50 text-green-700"

        div(class: "#{SURFACE_CARD} px-8 py-7") do
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
            meta_cell("Active since",  eff_from ? (fmt_date(Date.parse(eff_from.to_s)) rescue "—") : "—")
          end
        end
      end

      METHOD_LABELS = {
        "mobile_money"  => "Mobile Money",
        "card"          => "Card",
        "bank_transfer" => "Bank Transfer"
      }.freeze

      PROVIDER_LABELS = {
        "MTN_MOMO_GH"      => "MTN MoMo",
        "TELECEL_GH"       => "Telecel Cash",
        "AIRTELTIGO_GH"    => "AirtelTigo Money",
        "VISA"             => "Visa",
        "MASTERCARD"       => "Mastercard",
        "HUBTEL_GH"        => "Hubtel"
      }.freeze

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
              grouped_rules_table(rules)
            end
          end
        end
      end

      def grouped_rules_table(rules)
        catch_all  = rules.select { |r| r["method"].nil? && r["provider_code"].nil? }
        by_method  = rules
          .reject { |r| r["method"].nil? && r["provider_code"].nil? }
          .group_by { |r| r["method"] }

        div(class: "overflow-x-auto") do
          table(class: "w-full text-left") do
            thead do
              tr(class: "border-b border-gray-100") do
                th(class: "px-5 py-3 #{TYPE_MICRO} text-gray-400 font-semibold uppercase tracking-wide w-[160px]") { plain "Payment method" }
                th(class: "px-5 py-3 #{TYPE_MICRO} text-gray-400 font-semibold uppercase tracking-wide") { plain "Applies to" }
                th(class: "px-5 py-3 #{TYPE_MICRO} text-gray-400 font-semibold uppercase tracking-wide text-right") { plain "Rate" }
                th(class: "px-5 py-3 #{TYPE_MICRO} text-gray-400 font-semibold uppercase tracking-wide text-right") { plain "+ Fixed fee" }
                th(class: "px-5 py-3 #{TYPE_MICRO} text-gray-400 font-semibold uppercase tracking-wide text-right") { plain "Min charge" }
                th(class: "px-5 py-3 #{TYPE_MICRO} text-gray-400 font-semibold uppercase tracking-wide text-right") { plain "Cap" }
              end
            end
            tbody do
              by_method.each_with_index do |(method_key, method_rules), idx|
                method_rules.each_with_index do |r, ri|
                  first_in_group = ri.zero?
                  last_in_group  = ri == method_rules.size - 1
                  last_method    = idx == by_method.size - 1 && catch_all.empty?
                  rule_row_grouped(r, method_key, method_rules, first_in_group, last_in_group && last_method)
                end
              end

              catch_all.each do |r|
                fallback_row(r)
              end
            end
          end
        end
      end

      def rule_row_grouped(r, method_key, method_rules, first_in_group, is_last)
        cur        = @plan["currency"] || "GHS"
        has_specific = method_rules.any? { |x| x["provider_code"].present? }
        scope      = scope_label(r, has_specific)

        border_cls = is_last ? "" : "border-b border-gray-50"
        group_top  = first_in_group ? "pt-4" : "pt-2.5"
        group_bot  = (method_rules.last == r) ? "pb-4" : "pb-2.5"

        tr(class: "hover:bg-gray-50 transition-colors #{border_cls}") do
          td(class: "pl-5 pr-3 #{group_top} #{group_bot} align-top") do
            if first_in_group
              p(class: "text-[13px] font-semibold text-gray-800") do
                plain(METHOD_LABELS[method_key] || method_key.to_s.humanize)
              end
            end
          end
          td(class: "px-3 #{group_top} #{group_bot} align-top") do
            span(class: "text-[13px] text-gray-600") { plain scope }
          end
          rate_cells(r, cur)
        end
      end

      def fallback_row(r)
        cur = @plan["currency"] || "GHS"
        tr(class: "bg-gray-50/70 border-t border-gray-100 hover:bg-gray-50 transition-colors") do
          td(class: "pl-5 pr-3 py-3.5 align-top") do
            p(class: "text-[13px] font-semibold text-gray-500") { plain "All other methods" }
          end
          td(class: "px-3 py-3.5 align-top") do
            span(class: "text-[12px] text-gray-400") { plain "Fallback — applies if no specific rule matches" }
          end
          rate_cells(r, cur)
        end
      end

      def rate_cells(r, cur)
        pct   = r["percentage_bps"].to_i
        fixed = r["fixed_amount"].to_i
        min_f = r["minimum_fee"]
        max_f = r["maximum_fee"]

        pct_label   = pct.positive?   ? "#{sprintf('%.4f', pct / 100.0).sub(/0+$/, '').sub(/\.$/, '.0')}%" : "—"
        fixed_label = fixed.positive? ? format_money(fixed, currency: cur) : "—"
        min_label   = min_f ? format_money(min_f.to_i, currency: cur) : "—"
        max_label   = max_f ? format_money(max_f.to_i, currency: cur) : "—"

        td(class: "px-3 py-3 text-right tabular-nums text-[13px] font-semibold text-gray-800") { plain pct_label }
        td(class: "px-3 py-3 text-right tabular-nums text-[13px] text-gray-600") { plain fixed_label }
        td(class: "px-3 py-3 text-right tabular-nums #{TYPE_CAPTION}") { plain min_label }
        td(class: "pr-5 pl-3 py-3 text-right tabular-nums #{TYPE_CAPTION}") { plain max_label }
      end

      def scope_label(rule, has_specific_providers)
        code = rule["provider_code"]
        return PROVIDER_LABELS[code&.upcase] || code if code.present?

        has_specific_providers ? "All other networks" : "All providers"
      end

      def fee_mode_explainer
        mode = @plan["fee_mode"] || "deducted"

        div(class: "bg-blue-50 border border-blue-100 rounded-2xl px-6 py-5") do
          p(class: "text-[13px] font-semibold text-blue-800 mb-1.5") { plain "How your fees work" }
          if mode == "deducted"
            ul(class: "#{TYPE_CAPTION} text-blue-700 space-y-1 list-disc list-inside") do
              li { plain "Fees are automatically deducted from each settlement batch." }
              li { plain "Your settlement net amount = gross volume − platform fees." }
              li { plain "Fee and net amount are shown on each payment and each settlement batch." }
              li { plain "No separate invoice — everything is visible in your dashboard." }
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
