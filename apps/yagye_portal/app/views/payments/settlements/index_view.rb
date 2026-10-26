# frozen_string_literal: true

module Payments
  module Settlements
    class IndexView < ApplicationComponent
      include UI::Theme

      def initialize(settlements:, pagy:, state_filter: nil, query: nil, from: nil, to: nil,
                     stats: {}, ops_dashboard: {})
        @settlements   = settlements
        @pagy          = pagy
        @state_filter  = state_filter
        @query         = query
        @from          = from
        @to            = to
        @stats         = stats
        @ops_dashboard = ops_dashboard
      end

      def view_template
        mtd = @stats[:settled_mtd].to_i
        subtitle = mtd > 0 ? "#{format_money(mtd)} settled this month" \
                           : "Period-based reconciliation of funds owed to your account."

        render Layout::Shell.new(
          active_nav:  :settlements,
          title:       "Settlements",
          breadcrumbs: [ { label: "Settlements" } ]
        ) do
          render UI::PageHeader.new(title: "Settlements", subtitle: subtitle)
          ops_strip if @ops_dashboard.any?
          state_tabs
          settlements_table
        end
      end

      private

      # ── Ops KPI cards (internal only) ─────────────────────────────────────────

      def ops_strip
        float_balances    = Array(@ops_dashboard["float_balances"])
        merchant_payables = Array(@ops_dashboard["merchant_payables"])
        failed_count      = Array(@ops_dashboard["failed_disbursements"]).size

        payable_by_ccy = merchant_payables
          .group_by { |p| p["currency"] }
          .transform_values { |ps| ps.sum { |p| p["balance"].to_i } }
          .select { |_, v| v > 0 }

        float_by_ccy = float_balances
          .group_by { |f| f["currency"] }
          .transform_values { |fs| fs.sum { |f| f["balance"].to_i } }
          .select { |_, v| v > 0 }

        div(class: "grid grid-cols-3 gap-4 mb-6") do
          ops_payable_card(payable_by_ccy)
          ops_float_card(float_by_ccy)
          ops_failed_card(failed_count)
        end
      end

      def ops_payable_card(by_ccy)
        primary_ccy, primary_amt = by_ccy.max_by { |_, v| v }
        others = by_ccy.size - 1
        val  = primary_amt ? format_money(primary_amt, currency: primary_ccy) : "—"
        sub  = if primary_amt && others > 0
          "+ #{others} more #{others == 1 ? 'currency' : 'currencies'}"
        elsif !primary_amt
          "No outstanding payables"
        end
        ops_kpi_card(label: "Merchant Payables", value: val, icon: :wallet,
                     color: BRAND, tint: TINT_BRAND, sub: sub)
      end

      def ops_float_card(by_ccy)
        primary_ccy, primary_amt = by_ccy.max_by { |_, v| v }
        others = by_ccy.size - 1
        val  = primary_amt ? format_money(primary_amt, currency: primary_ccy) : "—"
        sub  = if primary_amt && others > 0
          "+ #{others} more #{others == 1 ? 'currency' : 'currencies'}"
        elsif !primary_amt
          "No positive float"
        end
        ops_kpi_card(label: "Provider Float", value: val, icon: :bank,
                     color: GREEN, tint: TINT_GREEN, sub: sub)
      end

      def ops_failed_card(count)
        alert = count > 0
        ops_kpi_card(label: "Failed Disbursements", value: count.to_s, icon: :alert_triangle,
                     color: alert ? RED : GREEN, tint: alert ? TINT_RED : TINT_GREEN,
                     sub: alert ? "Requires attention" : "All clear")
      end

      def ops_kpi_card(label:, value:, icon:, color:, tint:, sub: nil)
        div(class: "bg-white border border-gray-100 rounded-2xl p-[22px]") do
          div(class: "flex items-start justify-between mb-4") do
            div(class: "w-9 h-9 rounded-xl flex items-center justify-center",
                style: "background:#{tint}") do
              span(class: "flex w-[17px] h-[17px]", style: "color:#{color}") do
                render UI::Icon.new(icon, class: "w-full h-full")
              end
            end
          end
          p(class: TYPE_HEADING) { plain label }
          p(class: "#{TYPE_STAT} mt-2", style: "color:#{color}") { plain value }
          p(class: "#{TYPE_MICRO} mt-1.5 text-gray-400") { plain sub } if sub
        end
      end

      def settlements_table
        offset = @pagy ? @pagy.offset : 0

        render UI::Datatable.new(records: @settlements, pagy: @pagy,
                                 empty_message: empty_message) do |t|
          t.header { toolbar_content }

          t.column("#", class: "text-gray-400 tabular-nums text-right w-8") do |_, i|
            plain((offset + i + 1).to_s)
          end
          t.column("Merchant") do |s|
            name = s.merchant_name.to_s
            code = s.merchant_code.to_s
            uuid_like = code.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-/i)
            display_name = name.presence || (uuid_like ? "#{code.first(8)}…" : code)
            div do
              span(class: "text-[13px] font-medium text-gray-800") { plain display_name }
              if name.present? && name != code
                span(class: "block text-[11px] text-gray-400 font-mono mt-px") { plain code }
              end
            end
          end
          t.column("Ref") do |s|
            code = s.settlement_code.to_s
            ref  = code.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-/i) ? "#{code.first(8)}…" : code
            span(class: "#{TYPE_MONO} text-[12px]") { plain ref }
          end
          t.column("Amount", class: "text-right") do |s|
            div(class: "text-right") do
              span(class: "block text-[13px] font-semibold tabular-nums text-gray-900") do
                plain s.formatted_expected_net
              end
              if s.reported_net
                v = s.variance.to_i
                cls = v < 0 ? "text-red-600" : (v > 0 ? "text-green-600" : "text-gray-400")
                span(class: "block text-[11px] tabular-nums #{cls} mt-px") do
                  plain(v == 0 ? "matched" : "#{v > 0 ? '+' : ''}#{format_money(v.abs, currency: s.currency)} var.")
                end
              end
            end
          end
          t.column("Period") { |s| plain s.period_label }
          t.column("Rail") do |s|
            mode_cls = case s.mode
            when "live"       then "text-green-700 bg-green-50"
            when "sandbox"    then "text-amber-700 bg-amber-50"
            else                   "text-gray-500 bg-gray-100"
            end
            provider = s.provider_code.to_s
            div do
              span(class: "block text-[12px] font-mono text-gray-700 truncate max-w-[120px]") do
                plain provider.length > 20 ? provider.first(8) + "…" : provider
              end
              span(class: "inline-flex items-center px-[5px] py-px rounded text-[10px] font-semibold capitalize #{mode_cls} mt-[3px]") do
                plain s.mode
              end
            end
          end
          t.column("Status")     { |s| render UI::StatusBadge.new(status: s.state) }
          t.column("Value date") { |s| plain fmt_date(s.value_date) }

          t.actions do |s|
            a(href: settlement_path(s), class: DROPDOWN_ITEM) do
              render UI::Icon.new(:eye, class: ICON_SM)
              plain "View"
            end
          end
        end
      end

      # ── Toolbar ───────────────────────────────────────────────────────────────

      def toolbar_content
        filter_count = [ @state_filter.present?, @from.present?, @to.present? ].count(true)

        form(action: settlements_path, method: "get",
             data: { controller: "filter-form", filter_form_target: "form" }) do
          div(class: FILTER_SEARCH_WRAP) do
            span(class: "flex w-[13px] h-[13px] text-gray-400 flex-shrink-0") do
              render UI::Icon.new(:search, class: "w-full h-full")
            end
            input(type: "search", name: "q", value: @query,
                  placeholder: "Search settlement code…",
                  class: FILTER_SEARCH_INPUT)
          end
        end

        div(class: "flex items-center gap-2") do
          export_dropdown
          filter_btn(filter_count)
        end
      end

      def state_tabs
        pending    = @stats[:pending].to_i
        reconciled = @stats[:reconciled].to_i
        disputed   = @stats[:disputed].to_i

        render UI::Tabs.new do |t|
          t.tab "All",        href: settlements_path(q: @query),
                              active: @state_filter.nil?
          t.tab "Pending",    href: settlements_path(state: "pending",    q: @query),
                              active: @state_filter == "pending",
                              count: pending > 0 ? pending : nil
          t.tab "Reconciled", href: settlements_path(state: "reconciled", q: @query),
                              active: @state_filter == "reconciled",
                              count: reconciled > 0 ? reconciled : nil
          t.tab "Disputed",   href: settlements_path(state: "disputed",   q: @query),
                              active: @state_filter == "disputed",
                              count: disputed > 0 ? disputed : nil
        end
      end

      def export_dropdown
        base = { q: @query, state: @state_filter, from: @from, to: @to }.reject { |_, v| v.blank? }

        div(class: "relative", data: { controller: "dropdown" }) do
          button(type: "button",
                 class: "inline-flex items-center gap-[5px] px-3 h-8 border border-gray-200 rounded-[9px] " \
                        "text-[12.5px] font-medium text-gray-600 bg-white cursor-pointer transition-colors " \
                        "hover:border-gray-400 hover:text-gray-800",
                 data: { action: "click->dropdown#toggle" }) do
            render UI::Icon.new(:download, class: "w-3 h-3")
            plain "Export"
            render UI::Icon.new(:chev, class: "w-3 h-3 ml-px text-gray-400")
          end
          div(class: "#{DROPDOWN_MENU} top-full mt-1 right-0 min-w-[170px]",
              data: { dropdown_target: "menu" }) do
            p(class: DROPDOWN_TITLE) { plain "Export as" }
            a(href: settlements_path(base.merge(format: :csv)),  class: DROPDOWN_ITEM) do
              render UI::Icon.new(:file, class: ICON_SM)
              plain "CSV"
            end
            a(href: settlements_path(base.merge(format: :xlsx)), class: DROPDOWN_ITEM) do
              render UI::Icon.new(:file, class: ICON_SM)
              plain "Excel (.xlsx)"
            end
            a(href: settlements_path(base.merge(format: :pdf)),  class: DROPDOWN_ITEM) do
              render UI::Icon.new(:file, class: ICON_SM)
              plain "PDF"
            end
          end
        end
      end

      def filter_btn(filter_count)
        a(href: filter_settlements_path(q: @query, state: @state_filter, from: @from, to: @to),
          class: "inline-flex items-center gap-[5px] px-3 h-8 border rounded-[9px] " \
                 "text-[12.5px] font-medium bg-white cursor-pointer transition-colors no-underline " \
                 "#{filter_count > 0 ? 'border-gray-400 text-gray-900' : 'border-gray-200 text-gray-600'} " \
                 "hover:border-gray-400",
          data: { turbo_frame: "drawer-frame" }) do
          render UI::Icon.new(:filter, class: "w-3 h-3")
          plain "Filters"
          if filter_count > 0
            span(class: "ml-[2px] inline-flex items-center justify-center w-4 h-4 rounded-full " \
                        "bg-[#3D47F5] text-white text-[9px] font-bold leading-none") do
              plain filter_count.to_s
            end
          end
        end
      end

      def empty_message
        @state_filter.present? ? "No settlements match that state." : "Settlements will appear here once periods close."
      end
    end
  end
end
