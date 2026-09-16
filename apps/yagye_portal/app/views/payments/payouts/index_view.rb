# frozen_string_literal: true

module Payments
  module Payouts
    class IndexView < ApplicationComponent
      include UI::Theme

      def initialize(payouts:, pagy:, state_filter: nil, query: nil, stats: {})
        @payouts      = payouts
        @pagy         = pagy
        @state_filter = state_filter
        @query        = query
        @stats        = stats
      end

      def view_template
        render Layout::Shell.new(
          active_nav: :payouts,
          title:    "Payouts",
          subtitle: "Scheduled and completed disbursements to your bank account"
        ) do
          stat_band
          pending_requests_banner
          payouts_table
        end
      end

      private

      def stat_band
        cur             = @stats[:currency] || "GHS"
        paid_mtd        = @stats[:paid_mtd].to_i
        unsettled       = @stats[:unsettled].to_i
        next_value_date = @stats[:next_value_date]
        failed_30d      = @stats[:failed_30d].to_i

        paid_label      = "#{cur} #{"%.2f" % (paid_mtd / 100.0)}"
        unsettled_label = unsettled.positive? ? "#{cur} #{"%.2f" % (unsettled / 100.0)}" : "—"
        next_label      = next_value_date ? next_value_date.strftime("%d %b %Y") : "—"

        render UI::Grid.new(columns: 4) do
          stat_cell("Total paid (MTD)", paid_label,      icon: :trending_up,  color: GREEN,  tint: TINT_GREEN)
          stat_cell("Unsettled",        unsettled_label, icon: :clock,        color: AMBER,  tint: TINT_AMBER)
          stat_cell("Next settlement",  next_label,      icon: :calendar,     color: BRAND,  tint: TINT_BRAND)
          stat_cell("Failed (30d)",     failed_30d.to_s, icon: :alert_circle, color: RED,    tint: TINT_RED)
        end
      end

      # Ops: shows count of pending requests. Merchant: shows their own pending requests.
      def pending_requests_banner
        pending = PortalPayoutRequest.pending_review
        pending = pending.for_merchant(current_user.merchant_code) unless current_user.internal_staff?
        count   = pending.count
        return if count.zero?

        label = current_user.internal_staff? \
          ? "#{count} early payout request#{"s" if count != 1} awaiting review" \
          : "Your payout request is under review"

        div(class: "flex items-center justify-between rounded-2xl px-5 py-3.5 mb-4",
            style: "background:#fffbeb;border:1px solid #fde68a") do
          div(class: "flex items-center gap-3") do
            span(class: "flex-shrink-0") do
              render UI::Icon.new(:clock, class: "w-4 h-4", style: "color:#d97706")
            end
            p(class: "text-[13px] font-medium text-amber-800") { plain label }
          end
          a(href: payout_requests_path,
            class: "text-[12.5px] font-semibold no-underline whitespace-nowrap",
            style: "color:#d97706") do
            plain "View #{count == 1 ? "request" : "all"} →"
          end
        end
      end

      def payouts_table
        state_filter = @state_filter
        total        = @pagy.count

        render UI::Datatable.new(records: @payouts, pagy: @pagy,
                                 empty_message: empty_message) do |t|
          t.header do
            div(class: "flex items-center gap-2") do
              p(class: TYPE_TITLE) { plain "Payouts" }
              span(class: "bg-gray-100 text-gray-500 rounded-full px-[9px] py-[1px] text-[11.5px] font-semibold leading-[1.6]") { plain total.to_s } if total > 0
            end

            div(class: "flex items-center gap-2") do
              # Early payout request button — merchant only
              if helpers.policy(PortalPayoutRequest).create?
                a(href: new_payout_request_path,
                  class: "inline-flex items-center gap-1.5 h-8 px-3 rounded-[9px] text-[12.5px] font-semibold " \
                         "text-white no-underline",
                  style: "background:#3D47F5") do
                  render UI::Icon.new(:plus, class: "w-[11px] h-[11px]")
                  plain "Request payout"
                end
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
          end

          t.column("Payout code") { |p| span(class: TYPE_MONO) { plain p.payout_code.first(16) } }
          t.column("Amount", class: "text-right tabular-nums font-medium") { |p| plain p.formatted_amount }
          t.column("State")       { |p| render UI::StatusBadge.new(status: p.state) }
          t.column("Destination") { |p| plain p.destination_type&.humanize || "—" }
          t.column("Scheduled")   { |p| plain p.scheduled_for&.strftime("%d %b %Y") || "—" }
          t.column("Updated")     { |p| plain p.last_applied_at&.strftime("%d %b %Y, %H:%M") || "—" }

          t.actions do |p|
            a(href: payout_path(p), class: DROPDOWN_ITEM) do
              render UI::Icon.new(:eye, class: ICON_SM)
              plain "View"
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
