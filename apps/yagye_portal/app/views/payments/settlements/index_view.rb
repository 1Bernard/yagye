# frozen_string_literal: true

module Payments
  module Settlements
    class IndexView < ApplicationComponent
      include UI::Theme

      def initialize(settlements:, pagy:, state_filter: nil, query: nil, from: nil, to: nil, stats: {})
        @settlements  = settlements
        @pagy         = pagy
        @state_filter = state_filter
        @query        = query
        @from         = from
        @to           = to
        @stats        = stats
      end

      def view_template
        render Layout::Shell.new(
          active_nav: :settlements,
          title: "Settlements",
          subtitle: "Period-based reconciliation of funds owed to your account"
        ) do
          stat_band
          settlements_table
        end
      end

      private

      def stat_band
        mtd = @stats[:settled_mtd].to_i
        mtd_label = format_money(mtd)
        render UI::Grid.new(columns: 4) do
          stat_cell("Settled (MTD)", mtd_label,                      icon: :trending_up,  color: GREEN,  tint: TINT_GREEN)
          stat_cell("Pending",       @stats[:pending].to_s,          icon: :clock,        color: AMBER,  tint: TINT_AMBER)
          stat_cell("Reconciled",    @stats[:reconciled].to_s,       icon: :check_circle, color: BRAND,  tint: TINT_BRAND)
          stat_cell("Disputed",      @stats[:disputed].to_s,         icon: :alert_circle, color: RED,    tint: TINT_RED)
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
          t.column("Settlement")  { |s| span(class: TYPE_MONO) { plain s.settlement_code.first(16) } }
          t.column("Expected",    class: "text-right tabular-nums font-medium") { |s| plain s.formatted_expected_net }
          t.column("Reported",    class: "text-right tabular-nums") do |s|
            v   = s.variance
            cls = if v.nil?   then "text-[13px] text-gray-500"
                  elsif v < 0 then "text-[13px] font-semibold text-red-600"
                  elsif v > 0 then "text-[13px] font-semibold text-green-600"
                  else             "text-[13px] text-gray-700"
                  end
            span(class: cls) { plain s.formatted_reported_net }
          end
          t.column("Period")      { |s| plain s.period_label }
          t.column("State")       { |s| render UI::StatusBadge.new(status: s.state) }
          t.column("Value date")  { |s| plain s.value_date&.strftime("%d %b %Y") || "—" }

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
