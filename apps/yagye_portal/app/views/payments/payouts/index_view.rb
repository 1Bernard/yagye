# frozen_string_literal: true

module Payments
  module Payouts
    class IndexView < ApplicationComponent
      include UI::Theme

      def initialize(payouts:, pagy:, state_filter: nil, query: nil, from: nil, to: nil,
                     view: "list", stats: {})
        @payouts      = payouts
        @pagy         = pagy
        @state_filter = state_filter
        @query        = query
        @from         = from
        @to           = to
        @view         = view
        @stats        = stats
      end

      def view_template
        render Layout::Shell.new(
          active_nav: :payouts,
          title:    "Payouts",
          subtitle: "Scheduled and completed disbursements to your bank account"
        ) do
          render UI::PageHeader.new(
            title:    "Payouts",
            subtitle: "Scheduled and completed disbursements to your bank account."
          ) do
            if helpers.policy(PortalPayoutRequest).create?
              render UI::Button.new(variant: :primary, href: new_payout_request_path) do
                render UI::Icon.new(:plus, class: ICON_SM)
                plain "Request payout"
              end
            end
          end

          stat_band
          pending_requests_banner
          @view == "grid" ? payouts_grid_section : payouts_list_section
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

      def pending_requests_banner
        pending = PortalPayoutRequest.pending_review
        pending = pending.for_merchant(current_user.merchant_code) unless current_user.internal_staff?
        count   = pending.count
        return if count.zero?

        label = current_user.internal_staff? \
          ? "#{count} early payout request#{"s" if count != 1} awaiting review" \
          : "Your payout request is under review"

        div(class: "mb-4") do
          render UI::Notice.new(
            variant:      :warning,
            icon:         :clock,
            title:        label,
            action_label: "View #{count == 1 ? "request" : "all"}",
            action_href:  payout_requests_path
          )
        end
      end

      # ── Toolbar (shared) ─────────────────────────────────────────────────────

      def toolbar_content
        filter_count = [ @state_filter.present?, @from.present?, @to.present? ].count(true)

        form(action: payouts_path, method: "get",
             data: { controller: "filter-form", filter_form_target: "form" }) do
          input(type: "hidden", name: "view", value: @view)
          div(class: FILTER_SEARCH_WRAP) do
            span(class: "flex w-[13px] h-[13px] text-gray-400 flex-shrink-0") do
              render UI::Icon.new(:search, class: "w-full h-full")
            end
            input(type: "search", name: "q", value: @query,
                  placeholder: "Search payout code…",
                  class: FILTER_SEARCH_INPUT)
          end
        end

        div(class: "flex items-center gap-2") do
          export_dropdown
          filter_btn(filter_count)
          view_toggle
        end
      end

      def export_dropdown
        base = { q: @query, state: @state_filter, from: @from, to: @to, view: @view }.reject { |_, v| v.blank? }

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
            a(href: payouts_path(base.merge(format: :csv)),  class: DROPDOWN_ITEM) do
              render UI::Icon.new(:file, class: ICON_SM)
              plain "CSV"
            end
            a(href: payouts_path(base.merge(format: :xlsx)), class: DROPDOWN_ITEM) do
              render UI::Icon.new(:file, class: ICON_SM)
              plain "Excel (.xlsx)"
            end
            a(href: payouts_path(base.merge(format: :pdf)),  class: DROPDOWN_ITEM) do
              render UI::Icon.new(:file, class: ICON_SM)
              plain "PDF"
            end
          end
        end
      end

      def filter_btn(filter_count)
        a(href: filter_payouts_path(q: @query, state: @state_filter, from: @from, to: @to),
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

      def view_toggle
        base = { q: @query, state: @state_filter, from: @from, to: @to }.reject { |_, v| v.blank? }

        div(class: "flex items-center bg-gray-100 p-[3px] rounded-[10px] gap-[2px]") do
          [ [ :list, "list" ], [ :grid, "grid" ] ].each do |(icon_name, view_val)|
            active = @view == view_val
            attrs  = { href: payouts_path(base.merge(view: view_val)),
                       class: "flex items-center justify-center w-[30px] h-[30px] rounded-[8px] transition-all" }
            if active
              attrs[:class] += " bg-white text-gray-800"
              attrs[:style]  = "box-shadow:0 1px 3px rgba(0,0,0,0.10),0 1px 2px rgba(0,0,0,0.06)"
            else
              attrs[:class] += " text-gray-400 hover:text-gray-600"
            end
            a(**attrs) { render UI::Icon.new(icon_name, class: "w-[13px] h-[13px]") }
          end
        end
      end

      # ── Grid view ─────────────────────────────────────────────────────────────

      def payouts_grid_section
        div(class: "bg-white border border-gray-100 rounded-2xl mb-4") do
          div(class: "flex items-center justify-between px-5 py-3.5") do
            toolbar_content
          end
        end

        if @payouts.empty?
          div(class: "flex flex-col items-center justify-center text-center py-16") do
            div(class: "w-12 h-12 rounded-2xl icon-brand flex items-center justify-center mb-3") do
              span(class: "flex w-6 h-6") { render UI::Icon.new(:trending_up, class: "w-full h-full") }
            end
            p(class: "#{TYPE_BODY_MD} mb-1") { plain "No payouts found" }
            p(class: TYPE_CAPTION) { plain empty_message }
          end
        else
          div(class: "grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3") do
            @payouts.each { |p| payout_grid_card(p) }
          end
          if @pagy && @pagy.pages > 1
            render UI::Pagination.new(pagy: @pagy, class: "mt-4")
          end
        end
      end

      def payout_grid_card(p)
        a(href: payout_path(p),
          class: "group block bg-white border border-gray-100 rounded-2xl p-5 no-underline #{CARD_HOVER}") do
          div(class: "flex items-start justify-between mb-4") do
            div(class: "w-10 h-10 rounded-xl icon-brand flex items-center justify-center flex-shrink-0") do
              span(class: "flex w-5 h-5") { render UI::Icon.new(:trending_up, class: "w-full h-full") }
            end
            render UI::StatusBadge.new(status: p.state)
          end

          p(class: "text-[20px] font-bold text-gray-900 tabular-nums leading-tight mb-1") do
            plain p.formatted_amount
          end
          p(class: "#{TYPE_CAPTION} mb-4") { plain p.destination_type&.humanize || "—" }

          div(class: "flex items-center justify-between pt-3 border-t border-gray-50") do
            div do
              p(class: "text-[10.5px] text-gray-400 font-medium uppercase tracking-wide") { plain "Scheduled" }
              p(class: TYPE_BODY_MD) { plain p.scheduled_for&.strftime("%d %b %Y") || "—" }
            end
            span(class: "flex w-[13px] h-[13px] text-gray-300 flex-shrink-0 " \
                        "group-hover:text-gray-500 group-hover:translate-x-[2px] transition-all") do
              render UI::Icon.new(:chev_right, class: "w-full h-full")
            end
          end
        end
      end

      # ── List view ─────────────────────────────────────────────────────────────

      def payouts_list_section
        offset = @pagy ? @pagy.offset : 0

        render UI::Datatable.new(records: @payouts, pagy: @pagy,
                                 empty_message: empty_message) do |t|
          t.header { toolbar_content }

          t.column("#", class: "text-gray-400 tabular-nums text-right w-8") do |_, i|
            plain((offset + i + 1).to_s)
          end
          t.column("Payout code") { |p| span(class: TYPE_MONO) { plain p.payout_code.first(16) } }
          t.column("Amount", class: "text-right tabular-nums font-medium") { |p| plain p.formatted_amount }
          t.column("Destination") { |p| plain p.destination_type&.humanize || "—" }
          t.column("Status")       { |p| render UI::StatusBadge.new(status: p.state) }
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
