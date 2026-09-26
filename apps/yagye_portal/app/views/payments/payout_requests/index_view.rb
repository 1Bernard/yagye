# frozen_string_literal: true

module Payments
  module PayoutRequests
    class IndexView < ApplicationComponent
      include UI::Theme

      def initialize(requests:, pagy:, stats: {})
        @requests = requests
        @pagy     = pagy
        @stats    = stats
      end

      def view_template
        render Layout::Shell.new(
          active_nav: :payouts,
          title:      "Payout Requests",
          subtitle:   "Early payout requests submitted by merchants"
        ) do
          stat_band if @stats.any?
          requests_table
        end
      end

      private

      def stat_band
        render UI::Grid.new(columns: 3) do
          stat_cell("Pending Review", @stats[:pending].to_s,  icon: :clock,        color: AMBER, tint: TINT_AMBER)
          stat_cell("Approved",       @stats[:approved].to_s, icon: :check_circle, color: GREEN, tint: TINT_GREEN)
          stat_cell("Rejected",       @stats[:rejected].to_s, icon: :x_circle,     color: RED,   tint: TINT_RED)
        end
      end

      def requests_table
        render UI::Datatable.new(records: @requests, pagy: @pagy,
                                 empty_message: "No payout requests yet.") do |t|
          t.column("Merchant")  { |r| span(class: TYPE_MONO) { plain r.merchant_code } }
          t.column("Amount")    { |r| plain r.formatted_amount }
          t.column("Status")     { |r| render UI::StatusBadge.new(status: r.state) }
          t.column("Submitted") { |r| plain r.created_at.strftime("%d %b %Y, %H:%M") }
          t.column("Reviewed")  { |r| plain r.reviewed_at&.strftime("%d %b %Y") || "—" }

          t.actions do |r|
            a(href: payout_request_path(r), class: DROPDOWN_ITEM) do
              render UI::Icon.new(:eye, class: ICON_SM)
              plain "Review"
            end
          end
        end
      end
    end
  end
end
