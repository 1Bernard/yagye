# frozen_string_literal: true

module Payments
  module Settlements
    class IndexView < ApplicationComponent
      include UI::Theme

      def initialize(settlements:, pagy:, state_filter: nil, query: nil)
        @settlements  = settlements
        @pagy         = pagy
        @state_filter = state_filter
        @query        = query
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
        render UI::Grid.new(columns: 4) do
          stat_cell("Total settled (MTD)", "GHS 0.00", icon: :trending_up,  color: "#16a34a", tint: "rgba(22,163,74,0.08)")
          stat_cell("Pending",             "0",         icon: :clock,        color: "#d97706", tint: "rgba(217,119,6,0.08)")
          stat_cell("Reconciled",          "0",         icon: :check_circle, color: "#3D47F5", tint: "rgba(61,71,245,0.08)")
          stat_cell("Disputed",            "0",         icon: :alert_circle, color: "#dc2626", tint: "rgba(220,38,38,0.08)")
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
            span(class: variance_color(s.variance)) { plain s.formatted_reported_net }
          end
          t.column("State")       { |s| render UI::StatusBadge.new(status: s.state) }
          t.column("Value date")  { |s| s.value_date&.strftime("%d %b %Y") || "—" }

          t.actions do |s|
            a(href: settlement_path(s), class: DROPDOWN_ITEM) do
              render UI::Icon.new(:eye, class: ICON_SM)
              "View"
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
