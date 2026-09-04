# frozen_string_literal: true

module Payments
  module Payouts
    class IndexView < ApplicationComponent
      include UI::Theme

      def initialize(payouts:, pagy:, state_filter: nil, query: nil)
        @payouts      = payouts
        @pagy         = pagy
        @state_filter = state_filter
        @query        = query
      end

      def view_template
        render Layout::Shell.new(
          active_nav: :payouts,
          title: "Payouts",
          subtitle: "Scheduled and completed disbursements to your bank account"
        ) do
          stat_band
          payouts_table
        end
      end

      private

      def stat_band
        render UI::Grid.new(columns: 4) do
          stat_cell("Total paid (MTD)", "GHS 0.00", icon: :trending_up,  color: GREEN,  tint: TINT_GREEN)
          stat_cell("In-flight",        "0",         icon: :clock,        color: AMBER,  tint: TINT_AMBER)
          stat_cell("Next scheduled",   "—",         icon: :calendar,     color: BRAND,  tint: TINT_BRAND)
          stat_cell("Failed (30d)",     "0",         icon: :alert_circle, color: RED,    tint: TINT_RED)
        end
      end

      def payouts_table
        state_filter = @state_filter
        query        = @query
        total        = @pagy.count

        render UI::Datatable.new(records: @payouts, pagy: @pagy,
                                 empty_message: empty_message) do |t|
          t.header do
            div(class: "flex items-center gap-2") do
              p(class: TYPE_TITLE) { plain "Payouts" }
              span(class: "bg-gray-100 text-gray-500 rounded-full px-[9px] py-[1px] text-[11.5px] font-semibold leading-[1.6]") { plain total.to_s } if total > 0
            end

            form(action: payouts_path, method: "get",
                 class: "flex items-center gap-1.5",
                 data: { controller: "filter-form", filter_form_target: "form" }) do
              select(name: "state",
                     class: "h-8 border border-gray-200 rounded-[9px] px-[10px] text-[12.5px] font-medium text-gray-700 bg-white outline-none cursor-pointer",
                     data: { action: "change->filter-form#submit" }) do
                option(value: "", selected: state_filter.blank?) { plain "All states" }
                PortalPayout::STATES.each do |s|
                  option(value: s, selected: state_filter == s) { plain s.humanize }
                end
              end

              render UI::Button.new(variant: :secondary, type: "submit") do
                render UI::Icon.new(:filter, class: "w-[12px] h-[12px]")
                plain "Filter"
              end

              if state_filter.present?
                a(href: payouts_path, class: "text-[12px] text-gray-400 no-underline px-1 whitespace-nowrap") { plain "Clear" }
              end
            end
          end

          t.column("Payout code") { |p| span(class: TYPE_MONO) { p.payout_code.first(16) } }
          t.column("Amount", class: "text-right tabular-nums font-medium") { |p| p.formatted_amount }
          t.column("State")       { |p| render UI::StatusBadge.new(status: p.state) }
          t.column("Destination") { |p| p.destination_type&.humanize || "—" }
          t.column("Scheduled")   { |p| p.scheduled_for&.strftime("%d %b %Y") || "—" }
          t.column("Updated")     { |p| p.last_applied_at&.strftime("%d %b %Y, %H:%M") || "—" }

          t.actions do |p|
            a(href: payout_path(p), class: DROPDOWN_ITEM) do
              render UI::Icon.new(:eye, class: ICON_SM)
              "View"
            end
          end
        end
      end

      def empty_message
        @state_filter.present? ? "No payouts match that state." : "Payouts will appear here once disbursements are scheduled."
      end
    end
  end
end
