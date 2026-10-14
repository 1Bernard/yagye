# frozen_string_literal: true

module UI
  class PricingRateCard < ApplicationComponent
    include UI::Theme

    METHOD_LABELS = {
      "mobile_money"  => "Mobile Money",
      "card"          => "Card",
      "bank_transfer" => "Bank Transfer"
    }.freeze

    PROVIDER_LABELS = {
      "MTN_MOMO_GH"   => "MTN MoMo",
      "TELECEL_GH"    => "Telecel Cash",
      "AIRTELTIGO_GH" => "AirtelTigo Money",
      "VISA"          => "Visa",
      "MASTERCARD"    => "Mastercard",
      "HUBTEL_GH"     => "Hubtel"
    }.freeze

    def initialize(plan:)
      @plan = plan
    end

    def view_template
      rules = @plan["rules"] || []
      if rules.empty?
        div(class: "px-5 py-8 text-center") do
          p(class: TYPE_CAPTION) { plain "No pricing rules defined for this plan." }
        end
      else
        grouped_rules_table(rules)
      end
    end

    private

    def grouped_rules_table(rules)
      catch_all = rules.select { |r| r["method"].nil? && r["provider_code"].nil? }
      by_method = rules
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
            catch_all.each { |r| fallback_row(r) }
          end
        end
      end
    end

    def rule_row_grouped(r, method_key, method_rules, first_in_group, is_last)
      cur          = @plan["currency"] || "GHS"
      has_specific = method_rules.any? { |x| x["provider_code"].present? }
      scope        = scope_label(r, has_specific)
      border_cls   = is_last ? "" : "border-b border-gray-50"
      group_top    = first_in_group ? "pt-4" : "pt-2.5"
      group_bot    = (method_rules.last == r) ? "pb-4" : "pb-2.5"

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
  end
end
