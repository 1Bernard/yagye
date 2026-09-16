# frozen_string_literal: true

module Payments
  module Settlements
    class IndexView < ApplicationComponent
      include UI::Theme

      def initialize(settlements:, pagy:, state_filter: nil, query: nil, stats: {})
        @settlements  = settlements
        @pagy         = pagy
        @state_filter = state_filter
        @query        = query
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
        mtd_label = "GHS #{"%.2f" % (mtd / 100.0)}"
        render UI::Grid.new(columns: 4) do
          stat_cell("Settled (MTD)", mtd_label,                      icon: :trending_up,  color: GREEN,  tint: TINT_GREEN)
          stat_cell("Pending",       @stats[:pending].to_s,          icon: :clock,        color: AMBER,  tint: TINT_AMBER)
          stat_cell("Reconciled",    @stats[:reconciled].to_s,       icon: :check_circle, color: BRAND,  tint: TINT_BRAND)
          stat_cell("Disputed",      @stats[:disputed].to_s,         icon: :alert_circle, color: RED,    tint: TINT_RED)
        end
      end

      def settlements_table
        state_filter = @state_filter
        total        = @pagy.count

        render UI::Datatable.new(records: @settlements, pagy: @pagy,
                                 empty_message: empty_message) do |t|
          t.header do
            div(class: "flex items-center gap-2") do
              p(class: TYPE_TITLE) { plain "Settlements" }
              span(class: "bg-gray-100 text-gray-500 rounded-full px-[9px] py-[1px] text-[11.5px] font-semibold leading-[1.6]") { plain total.to_s } if total > 0
            end

            form(action: settlements_path, method: "get",
                 class: "flex items-center gap-1.5",
                 data: { controller: "filter-form", filter_form_target: "form" }) do
              select(name: "state",
                     class: "h-8 border border-gray-200 rounded-[9px] px-[10px] text-[12.5px] font-medium text-gray-700 bg-white outline-none cursor-pointer",
                     data: { action: "change->filter-form#submit" }) do
                option(value: "", selected: state_filter.blank?) { plain "All states" }
                PortalSettlement::STATES.each do |s|
                  option(value: s, selected: state_filter == s) { plain s.humanize }
                end
              end

              render UI::Button.new(variant: :secondary, type: "submit") do
                render UI::Icon.new(:filter, class: "w-[12px] h-[12px]")
                plain "Filter"
              end

              if state_filter.present?
                a(href: settlements_path, class: "text-[12px] text-gray-400 no-underline px-1 whitespace-nowrap") { plain "Clear" }
              end
            end
          end

          t.column("Settlement")  { |s| span(class: TYPE_MONO) { plain s.settlement_code.first(16) } }
          t.column("Period")      { |s| plain s.period_label }
          t.column("Expected",    class: "text-right tabular-nums font-medium") { |s| plain s.formatted_expected_net }
          t.column("Reported",    class: "text-right tabular-nums") do |s|
            v   = s.variance
            cls = if v.nil?      then "text-[13px] text-gray-500"
                  elsif v < 0    then "text-[13px] font-semibold text-red-600"
                  elsif v > 0    then "text-[13px] font-semibold text-green-600"
                  else                "text-[13px] text-gray-700"
                  end
            span(class: cls) { plain s.formatted_reported_net }
          end
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

      def variance_color(variance)
        return "text-[13px] text-gray-500" if variance.nil?

        if variance.negative?
          "text-[13px] font-semibold text-red-600"
        elsif variance.positive?
          "text-[13px] font-semibold text-green-600"
        else
          "text-[13px] text-gray-700"
        end
      end

      def empty_message
        @state_filter.present? ? "No settlements match that state." : "Settlements will appear here once periods close."
      end
    end
  end
end
