# frozen_string_literal: true

module Checkout
  module Settings
    class IndexView < ApplicationComponent
      include UI::Theme

      TABS = [
        { key: "methods",   label: "Payment Methods", icon: :credit_card },
        { key: "analytics", label: "Conversion Analytics", icon: :trending_up }
      ].freeze

      METHOD_META = {
        "mobile_money"  => { label: "Mobile Money",   desc: "MTN MoMo, Telecel Cash, AirtelTigo Money", icon: :smartphone,   color: "#3D47F5" },
        "card"          => { label: "Card",            desc: "Visa, Mastercard and major card networks",  icon: :credit_card,  color: "#10b981" },
        "bank_transfer" => { label: "Bank Transfer",   desc: "Direct bank account payments",              icon: :bank,         color: "#f59e0b" }
      }.freeze

      def initialize(tab: "methods", allowed_methods: %w[mobile_money card bank_transfer], analytics: nil)
        @tab             = tab
        @allowed_methods = Array(allowed_methods)
        @analytics       = analytics || {}
      end

      def view_template
        render Layout::Shell.new(
          active_nav: :checkout_settings,
          title:      "Checkout Settings",
          breadcrumbs: [{ label: "Checkout Settings" }]
        ) do
          div(class: "flex gap-10 items-start") do
            settings_sidebar
            div(class: "flex-1 min-w-0") do
              case @tab
              when "methods"   then methods_panel
              when "analytics" then analytics_panel
              end
            end
          end
        end
      end

      private

      # ── Sidebar nav ─────────────────────────────────────────────────────────────

      def settings_sidebar
        nav(class: "w-[172px] flex-shrink-0 sticky top-6 flex flex-col gap-5") do
          div do
            p(class: "text-[10.5px] font-semibold text-gray-400 uppercase tracking-[0.07em] mb-[6px] px-3") do
              plain "Checkout"
            end
            div(class: "flex flex-col gap-[2px]") do
              TABS.each { |tab| tab_link(tab) }
            end
          end
        end
      end

      def tab_link(tab)
        active = @tab == tab[:key]
        href   = checkout_settings_path(tab: tab[:key])
        cls    = "flex items-center gap-[10px] px-3 py-[8px] rounded-[10px] text-[13px] no-underline transition-colors"

        if active
          a(href: href,
            class: "#{cls} font-semibold",
            style: "background:rgba(61,71,245,0.09);color:#{BRAND}") do
            span(class: "flex w-[14px] h-[14px] flex-shrink-0", style: "color:#{BRAND}") do
              render UI::Icon.new(tab[:icon], class: "w-full h-full")
            end
            plain tab[:label]
          end
        else
          a(href: href,
            class: "#{cls} font-medium text-gray-500 hover:bg-gray-50 hover:text-gray-700") do
            span(class: "flex w-[14px] h-[14px] flex-shrink-0 text-gray-400") do
              render UI::Icon.new(tab[:icon], class: "w-full h-full")
            end
            plain tab[:label]
          end
        end
      end

      # ── Payment Methods panel ────────────────────────────────────────────────────

      def methods_panel
        div(class: "flex flex-col gap-5") do
          div(class: "bg-white border border-gray-100 rounded-2xl overflow-hidden") do
            div(class: "px-6 py-5 border-b border-gray-100") do
              p(class: TYPE_TITLE) { plain "Payment Methods" }
              p(class: "#{TYPE_CAPTION} mt-[3px]") do
                plain "Control which payment methods appear on your checkout pages and payment links."
              end
            end

            form(action: checkout_settings_payment_methods_path, method: "post") do
              input(type: "hidden", name: "_method",            value: "patch")
              input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)

              div(class: "divide-y divide-gray-50") do
                METHOD_META.each { |key, meta| method_row(key, meta) }
              end

              div(class: "px-6 py-4 border-t border-gray-100 flex items-center justify-between") do
                p(class: TYPE_CAPTION) { plain "At least one method must remain enabled." }
                render UI::Button.new(variant: :primary, type: "submit") { plain "Save changes" }
              end
            end
          end
        end
      end

      def method_row(key, meta)
        enabled = @allowed_methods.include?(key)

        div(class: "px-6 py-4 flex items-center gap-4") do
          div(class: "w-10 h-10 rounded-xl flex items-center justify-center flex-shrink-0",
              style: "background:#{enabled ? "rgba(61,71,245,0.09)" : "#F3F4F6"}") do
            span(class: "flex w-[18px] h-[18px]",
                 style: "color:#{enabled ? BRAND : "#9CA3AF"}") do
              render UI::Icon.new(meta[:icon], class: "w-full h-full")
            end
          end

          div(class: "flex-1 min-w-0") do
            p(class: "text-[13px] font-semibold text-gray-800") { plain meta[:label] }
            p(class: "#{TYPE_CAPTION} mt-[2px]") { plain meta[:desc] }
          end

          label(class: "relative inline-flex items-center cursor-pointer flex-shrink-0") do
            input(
              type:    "checkbox",
              name:    "allowed_methods[]",
              value:   key,
              checked: enabled,
              class:   "sr-only peer",
              id:      "method_#{key}"
            )
            div(
              class: "w-10 h-6 bg-gray-200 peer-focus:outline-none rounded-full peer " \
                     "peer-checked:after:translate-x-full rtl:peer-checked:after:-translate-x-full " \
                     "peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] " \
                     "after:start-[2px] after:bg-white after:border-gray-300 after:border " \
                     "after:rounded-full after:h-5 after:w-5 after:transition-all",
              style: enabled ? "background-color:#{BRAND}" : ""
            )
          end
        end
      end

      # ── Conversion Analytics panel ───────────────────────────────────────────────

      def analytics_panel
        div(class: "flex flex-col gap-5") do
          # Header card
          div(class: "bg-white border border-gray-100 rounded-2xl overflow-hidden") do
            div(class: "px-6 py-5 border-b border-gray-100") do
              div(class: "flex items-center justify-between") do
                div do
                  p(class: TYPE_TITLE) { plain "Conversion Analytics" }
                  p(class: "#{TYPE_CAPTION} mt-[3px]") { plain "Checkout funnel for the last 30 days." }
                end
                span(class: "text-[11px] font-medium text-gray-400 flex items-center gap-1") do
                  span(class: "flex w-[11px] h-[11px] text-gray-300") { render UI::Icon.new(:clock, class: "w-full h-full") }
                  plain "Last 30 days"
                end
              end
            end

            # Funnel stat grid
            funnel_stats
          end

          # Method breakdown
          method_breakdown_card unless @analytics["method_breakdown"].blank?
        end
      end

      FUNNEL_STEPS = [
        { key: "sessions_started",  label: "Sessions Started",   icon: :eye,          color: "#6366f1" },
        { key: "method_selected",   label: "Method Selected",    icon: :credit_card,  color: "#3D47F5" },
        { key: "payment_attempted", label: "Payment Attempted",  icon: :arrow_right,  color: "#f59e0b" },
        { key: "completed",         label: "Completed",          icon: :check_circle, color: "#10b981" }
      ].freeze

      def funnel_stats
        started = (@analytics["sessions_started"] || 0).to_i

        div(class: "grid grid-cols-2 divide-x divide-y divide-gray-50") do
          FUNNEL_STEPS.each_with_index do |step, idx|
            count = (@analytics[step[:key]] || 0).to_i
            pct   = started > 0 ? (count.to_f / started * 100).round(1) : 0.0
            is_last = idx == FUNNEL_STEPS.size - 1

            div(class: "px-6 py-5 flex flex-col gap-[6px] #{is_last ? 'col-span-2' : ''}") do
              div(class: "flex items-center gap-2 mb-1") do
                span(class: "flex w-[13px] h-[13px] flex-shrink-0",
                     style: "color:#{step[:color]}") do
                  render UI::Icon.new(step[:icon], class: "w-full h-full")
                end
                p(class: "text-[11px] font-semibold text-gray-500 uppercase tracking-[0.06em]") do
                  plain step[:label]
                end
              end

              p(class: "text-[28px] font-extrabold tabular-nums leading-none",
                style: "color:#{step[:color]}") do
                plain count.to_s
              end

              if is_last
                # Conversion rate highlight
                rate = (@analytics["conversion_rate"] || 0.0).to_f
                p(class: "text-[12px] font-medium text-gray-400") do
                  plain "#{rate}% overall conversion rate"
                end
              elsif idx > 0 && started > 0
                # Show drop-off as a simple progress bar
                div(class: "flex items-center gap-2 mt-1") do
                  div(class: "flex-1 h-1 bg-gray-100 rounded-full overflow-hidden") do
                    div(class: "h-full rounded-full", style: "width:#{[pct, 100].min}%;background:#{step[:color]}")
                  end
                  span(class: "text-[10.5px] font-semibold", style: "color:#{step[:color]}") do
                    plain "#{pct}%"
                  end
                end
              end
            end
          end
        end
      end

      def method_breakdown_card
        breakdown = Array(@analytics["method_breakdown"])
        total     = breakdown.sum { |b| (b["count"] || b[:count] || 0).to_i }

        div(class: "bg-white border border-gray-100 rounded-2xl overflow-hidden") do
          div(class: "px-6 py-5 border-b border-gray-100") do
            p(class: TYPE_TITLE) { plain "Method Preference" }
            p(class: "#{TYPE_CAPTION} mt-[3px]") { plain "Which payment methods customers selected." }
          end

          div(class: "px-6 py-5 flex flex-col gap-4") do
            breakdown.sort_by { |b| -(b["count"] || b[:count] || 0).to_i }.each do |entry|
              method = entry["method"] || entry[:method]
              count  = (entry["count"] || entry[:count] || 0).to_i
              meta   = METHOD_META[method] || { label: method.to_s.tr("_", " ").capitalize, color: "#6b7280" }
              pct    = total > 0 ? (count.to_f / total * 100).round(1) : 0.0

              div do
                div(class: "flex items-center justify-between mb-[6px]") do
                  p(class: "text-[12.5px] font-semibold text-gray-700") { plain meta[:label] }
                  p(class: "text-[12px] font-medium text-gray-500") do
                    plain "#{count} (#{pct}%)"
                  end
                end
                div(class: "h-2 bg-gray-100 rounded-full overflow-hidden") do
                  div(class: "h-full rounded-full transition-all",
                      style: "width:#{[pct, 100].min}%;background:#{meta[:color]}")
                end
              end
            end
          end
        end
      end
    end
  end
end
