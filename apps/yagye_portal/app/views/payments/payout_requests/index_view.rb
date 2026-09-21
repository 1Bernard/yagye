# frozen_string_literal: true

module Payments
  module PayoutRequests
    class IndexView < ApplicationComponent
      include UI::Theme

      def initialize(requests:, pagy:)
        @requests = requests
        @pagy     = pagy
      end

      def view_template
        render Layout::Shell.new(
          active_nav: :payouts,
          title:      "Payout Requests",
          subtitle:   "Early payout requests submitted by merchants"
        ) do
          render UI::Datatable.new(records: @requests, pagy: @pagy,
                                   empty_message: "No payout requests yet.") do |t|
            t.header do
              div(class: "flex items-center gap-2") do
                p(class: TYPE_TITLE) { plain "Payout Requests" }
              end
            end

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
end
