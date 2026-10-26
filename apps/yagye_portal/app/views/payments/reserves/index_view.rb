# frozen_string_literal: true

module Payments
  module Reserves
    class IndexView < ApplicationComponent
      include UI::Theme

      PER_PAGE = 25

      STATE_STYLES = {
        "pending"  => { badge: STATUS_WARNING, label: "Held"     },
        "released" => { badge: STATUS_SUCCESS, label: "Released" },
        "drawn"    => { badge: STATUS_FAILED,  label: "Drawn"    }
      }.freeze

      def initialize(policy: nil, summary: {}, holds: [], forecast: {}, state_filter: nil,
                     q: nil, from: nil, to: nil, page: 1, total: 0)
        @policy       = policy
        @summary      = summary
        @holds        = holds
        @forecast     = forecast
        @state_filter = state_filter
        @q            = q
        @from         = from
        @to           = to
        @page         = page
        @total        = total
      end

      def view_template
        render Layout::Shell.new(
          active_nav:  :reserves,
          title:       "Rolling Reserve",
          breadcrumbs: [ { label: "Reserves" } ]
        ) do
          page_header

          if @policy.nil? && @holds.empty?
            no_policy_state
          else
            div(class: "flex flex-col gap-5") do
              policy_status_notice if notice_status
              summary_stats
              forecast_card if forecast_present?
              state_tabs
              holds_card
            end
          end
        end
      end

      private

      # ── Page header with policy context inline ────────────────────────────────

      def page_header
        div(class: "flex items-start justify-between mb-6") do
          div do
            div(class: "flex items-center gap-2.5 mb-1") do
              h1(class: TYPE_DISPLAY) { plain "Rolling Reserve" }
              policy_status_badge if @policy
            end
            if @policy
              p(class: TYPE_CAPTION) do
                plain policy_summary_line
              end
            else
              p(class: TYPE_CAPTION) do
                plain "Funds withheld from settlements to cover chargebacks and disputes."
              end
            end
          end
        end
      end

      def policy_status_badge
        status = @policy["status"] || (@policy["approved_by"] ? "active" : "pending_approval")
        case status
        when "active"                then span(class: "#{BADGE} #{STATUS_SUCCESS}") { plain "Active" }
        when "awaiting_merchant_ack" then span(class: "#{BADGE} #{STATUS_WARNING}") { plain "Awaiting acknowledgment" }
        when "inactive"              then span(class: "#{BADGE} #{STATUS_NEUTRAL}") { plain "Inactive" }
        else                              span(class: "#{BADGE} #{STATUS_NEUTRAL}") { plain "Pending approval" }
        end
      end

      def policy_summary_line
        return "Funds withheld from settlements to cover chargebacks and disputes." unless @policy

        parts = []
        if @policy["kind"] == "rolling" && @policy["percentage_bps"]
          parts << "#{(@policy["percentage_bps"].to_f / 100).round(2)}% rolling reserve"
        elsif @policy["kind"] == "fixed" && @policy["fixed_amount"]
          parts << "#{format_amount(@policy["fixed_amount"], @policy["currency"] || "GHS")} fixed reserve"
        else
          parts << "Ad hoc reserve"
        end
        parts << "#{@policy["hold_days"] || 90}-day hold period"
        parts << "Set by Yagye Risk Team"
        parts.join(" · ")
      end

      # ── Policy acknowledgment / pending notice ────────────────────────────────

      def notice_status
        return nil unless @policy
        s = @policy["status"] || (@policy["approved_by"] ? "active" : "pending_approval")
        s.in?(%w[pending_approval awaiting_merchant_ack]) ? s : nil
      end

      def policy_status_notice
        case notice_status
        when "pending_approval"
          div(class: "bg-gray-50 border border-gray-200 rounded-xl px-5 py-4") do
            p(class: "text-[12.5px] font-semibold text-gray-700 mb-1") { plain "Reserve policy under review" }
            p(class: "#{TYPE_CAPTION} text-gray-500") do
              plain "A reserve policy has been set for your account and is undergoing internal approval. " \
                    "No funds will be withheld until it is approved and you have acknowledged the terms."
            end
          end
        when "awaiting_merchant_ack"
          auto_date = begin
                        Time.parse(@policy["auto_activates_at"].to_s).strftime("%-d %B %Y")
                      rescue ArgumentError, TypeError
                        "7 days from now"
                      end
          div(class: "bg-amber-50 border border-amber-200 rounded-xl px-5 py-5") do
            div(class: "flex items-start gap-3 mb-3") do
              span(class: "flex w-5 h-5 text-amber-500 flex-shrink-0 mt-0.5") do
                render UI::Icon.new(:alert_circle, class: "w-full h-full")
              end
              div do
                p(class: "text-[13px] font-semibold text-amber-900 mb-0.5") do
                  plain "Action required: Acknowledge your reserve policy"
                end
                p(class: "#{TYPE_CAPTION} text-amber-700") do
                  plain "Yagye has applied a reserve policy to your account. Please review the terms above " \
                        "and acknowledge your acceptance. If you take no action, the policy will activate " \
                        "automatically on #{auto_date}."
                end
              end
            end
            form(action: acknowledge_reserve_path(@policy["id"]), method: "post") do
              input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
              button(type: "submit", class: BTN_PRIMARY.to_s) do
                render UI::Icon.new(:check_circle, class: ICON_SM)
                plain "I acknowledge and accept this reserve policy"
              end
            end
          end
        end
      end

      # ── No policy state ───────────────────────────────────────────────────────

      def no_policy_state
        div(class: "#{SURFACE_CARD} px-8 py-16 flex flex-col items-center text-center gap-4") do
          div(class: "w-12 h-12 rounded-2xl flex items-center justify-center mb-2",
              style: "background:#{TINT_AMBER}") do
            span(class: "flex w-[22px] h-[22px]", style: "color:#{AMBER}") do
              render UI::Icon.new(:lock, class: "w-full h-full")
            end
          end
          p(class: TYPE_TITLE) { plain "No reserve policy set" }
          p(class: "#{TYPE_CAPTION} max-w-sm") do
            plain "Your account does not currently have an active reserve policy. Contact your Yagye account manager if you have questions."
          end
          div(class: "mt-4 bg-amber-50 border border-amber-100 rounded-xl px-5 py-4 text-left max-w-md") do
            p(class: "text-[12px] font-semibold text-amber-800 mb-1") { plain "How reserves work" }
            ul(class: "#{TYPE_CAPTION} text-amber-700 space-y-1 list-disc list-inside") do
              li { plain "A rolling reserve (typically 5–10%) is withheld from each settlement." }
              li { plain "Held funds are released on a 90-day rolling basis." }
              li { plain "Dispute losses are deducted from your reserve before release." }
            end
          end
        end
      end

      # ── Summary stats ─────────────────────────────────────────────────────────

      def summary_stats
        currency = @policy&.dig("currency") || "GHS"

        render UI::Grid.new(columns: 3) do
          stat_cell(
            "Currently Held",
            format_amount(@summary["pending_amount"], currency),
            sub:   "#{@summary["pending_count"] || 0} active holds",
            icon:  :lock,
            color: AMBER,
            tint:  TINT_AMBER
          )
          stat_cell(
            "Total Released",
            format_amount(@summary["released_amount"], currency),
            sub:   "#{@summary["released_count"] || 0} released",
            icon:  :check_circle,
            color: GREEN,
            tint:  TINT_GREEN
          )
          stat_cell(
            "Drawn for Disputes",
            format_amount(@summary["drawn_amount"], currency),
            sub:   "#{@summary["drawn_count"] || 0} draws",
            icon:  :flag,
            color: RED,
            tint:  TINT_RED
          )
        end
      end

      def stat_cell(label, value, sub:, icon:, color:, tint:)
        div(class: "#{SURFACE_CARD} px-5 py-5 flex items-start gap-4") do
          div(class: "w-10 h-10 rounded-xl flex items-center justify-center flex-shrink-0",
              style: "background:#{tint}") do
            span(class: "flex w-[18px] h-[18px]", style: "color:#{color}") do
              render UI::Icon.new(icon, class: "w-full h-full")
            end
          end
          div do
            p(class: "text-[20px] font-bold tabular-nums text-gray-900 leading-tight") { plain value }
            p(class: "#{TYPE_MICRO} mt-[3px]") { plain label }
            p(class: "#{TYPE_CAPTION} mt-1") { plain sub }
          end
        end
      end

      # ── Upcoming releases forecast ────────────────────────────────────────────

      def forecast_card
        currency = @policy&.dig("currency") || "GHS"
        buckets  = [
          { label: "Next 30 days", key: "next_30_days",    color: GREEN, tint: TINT_GREEN },
          { label: "Days 31–60",   key: "next_31_60_days", color: BRAND, tint: TINT_BRAND },
          { label: "Days 61–90",   key: "next_61_90_days", color: AMBER, tint: TINT_AMBER }
        ]

        div(class: "#{SURFACE_CARD} overflow-hidden") do
          div(class: "px-6 py-5 border-b border-gray-100") do
            p(class: TYPE_TITLE) { plain "Upcoming releases" }
            p(class: "#{TYPE_CAPTION} mt-[3px]") do
              plain "Estimated amounts releasing from your reserve over the next 90 days."
            end
          end
          div(class: "grid grid-cols-3 divide-x divide-gray-100") do
            buckets.each do |b|
              amount = @forecast[b[:key]].to_i
              div(class: "px-6 py-5 flex items-start gap-3") do
                div(class: "w-8 h-8 rounded-xl flex items-center justify-center flex-shrink-0 mt-[2px]",
                    style: "background:#{b[:tint]}") do
                  span(class: "flex w-[15px] h-[15px]", style: "color:#{b[:color]}") do
                    render UI::Icon.new(:clock, class: "w-full h-full")
                  end
                end
                div do
                  p(class: TYPE_MICRO) { plain b[:label] }
                  p(class: "text-[17px] font-bold tabular-nums text-gray-900 mt-1 leading-tight") do
                    plain format_amount(amount, currency)
                  end
                end
              end
            end
          end
          if @forecast["beyond_90_days"].to_i > 0
            div(class: "px-6 py-3 border-t border-gray-100 bg-gray-50") do
              p(class: TYPE_CAPTION) do
                plain "Plus #{format_amount(@forecast["beyond_90_days"].to_i, currency)} releasing after 90 days."
              end
            end
          end
        end
      end

      # ── State filter tabs — standalone above the holds card ───────────────────

      def state_tabs
        search_params = { q: @q, from: @from, to: @to }.compact
        render UI::Tabs.new do |t|
          t.tab "All",      href: reserves_path(**search_params),                    active: @state_filter.nil?,          count: total_count
          t.tab "Held",     href: reserves_path(state: "pending",  **search_params), active: @state_filter == "pending",  count: @summary["pending_count"].to_i
          t.tab "Released", href: reserves_path(state: "released", **search_params), active: @state_filter == "released", count: @summary["released_count"].to_i
          t.tab "Drawn",    href: reserves_path(state: "drawn",    **search_params), active: @state_filter == "drawn",    count: @summary["drawn_count"].to_i
        end
      end

      # ── Holds card ────────────────────────────────────────────────────────────

      def holds_card
        div(class: "#{SURFACE_CARD} overflow-hidden") do
          div(class: "px-6 py-5 border-b border-gray-100") do
            p(class: TYPE_TITLE) { plain "Reserve holds" }
            p(class: "#{TYPE_CAPTION} mt-[3px]") { plain "Individual amounts withheld, one per payment." }
          end

          holds_toolbar

          if @holds.empty?
            div(class: "px-6 py-12 text-center") do
              p(class: TYPE_CAPTION) do
                if @q.present? || @from.present? || @to.present? || @state_filter
                  plain "No holds match your filters."
                else
                  plain "No reserve holds yet."
                end
              end
            end
          else
            div(class: "overflow-x-auto") do
              table(class: "w-full text-left") do
                thead do
                  tr(class: "border-b border-gray-100 bg-gray-50/60") do
                    th(class: "px-6 py-3 #{TYPE_MICRO}") { plain "Payment" }
                    th(class: "px-6 py-3 #{TYPE_MICRO} text-right") { plain "Amount held" }
                    th(class: "px-6 py-3 #{TYPE_MICRO}") { plain "Status" }
                    th(class: "px-6 py-3 #{TYPE_MICRO}") { plain "Held on" }
                    th(class: "px-6 py-3 #{TYPE_MICRO}") { plain "Release" }
                  end
                end
                tbody do
                  @holds.each { |h| hold_row(h) }
                end
              end
            end

            if @total > PER_PAGE
              div(class: "px-6 py-4 border-t border-gray-100 flex items-center justify-between") do
                p(class: TYPE_CAPTION) do
                  from_row = (@page - 1) * PER_PAGE + 1
                  to_row   = [ from_row + PER_PAGE - 1, @total ].min
                  plain "#{from_row}–#{to_row} of #{@total}"
                end
                div(class: "flex gap-2") do
                  if @page > 1
                    render UI::Button.new(variant: :secondary,
                                         href: reserves_path(page_params(@page - 1))) { plain "← Previous" }
                  end
                  if @page * PER_PAGE < @total
                    render UI::Button.new(variant: :secondary,
                                         href: reserves_path(page_params(@page + 1))) { plain "Next →" }
                  end
                end
              end
            end
          end
        end
      end

      def holds_toolbar
        filter_count = [ @q, @from, @to ].count(&:present?)
        export_base  = { q: @q, from: @from, to: @to }.compact

        div(class: "px-4 py-2.5 border-b border-gray-100 flex items-center gap-2") do
          # Search form — fixed width, doesn't swallow the whole row
          form(action: reserves_path, method: "get",
               class: "w-56 flex-shrink-0",
               data: { controller: "filter-form", filter_form_delay_value: "400" }) do
            input(type: "hidden", name: "state", value: @state_filter) if @state_filter.present?
            input(type: "hidden", name: "from",  value: @from)         if @from.present?
            input(type: "hidden", name: "to",    value: @to)           if @to.present?
            div(class: "#{FILTER_SEARCH_WRAP} rounded-[9px]") do
              span(class: "flex w-4 h-4 text-gray-400 flex-shrink-0") do
                render UI::Icon.new(:search, class: "w-full h-full")
              end
              input(
                type:        "text",
                name:        "q",
                value:       @q,
                placeholder: "Search by reference…",
                class:       "#{FILTER_SEARCH_INPUT} w-full",
                data:        { action: "input->filter-form#submit" }
              )
            end
          end

          # Spacer
          div(class: "flex-1")

          # Right controls group
          div(class: "flex items-center gap-2") do
            # Export dropdown
            div(class: "relative", data: { controller: "dropdown" }) do
              button(
                type:  "button",
                class: "inline-flex items-center gap-[5px] px-3 h-8 border border-gray-200 " \
                       "rounded-[9px] text-[12.5px] font-medium text-gray-600 bg-white " \
                       "cursor-pointer hover:border-gray-400 hover:text-gray-800 transition-colors",
                data:  { action: "click->dropdown#toggle" }
              ) do
                render UI::Icon.new(:download, class: "w-3 h-3")
                plain "Export"
                render UI::Icon.new(:chev, class: "w-3 h-3 ml-px text-gray-400")
              end
              div(class: "#{DROPDOWN_MENU} top-full mt-1 right-0 min-w-[170px]",
                  data: { dropdown_target: "menu" }) do
                p(class: DROPDOWN_TITLE) { plain "Export as" }
                a(href: export_reserves_path(format: :csv, **export_base), class: DROPDOWN_ITEM) do
                  render UI::Icon.new(:file, class: ICON_SM)
                  plain "CSV"
                end
                a(href: export_reserves_path(format: :xlsx, **export_base), class: DROPDOWN_ITEM) do
                  render UI::Icon.new(:file, class: ICON_SM)
                  plain "Excel (.xlsx)"
                end
              end
            end

            # Filter drawer trigger
            active_filter = filter_count > 0
            filter_classes = "inline-flex items-center gap-[5px] px-3 h-8 border rounded-[9px] " \
                             "text-[12.5px] font-medium no-underline transition-colors " +
                             (active_filter ? "border-indigo-300 bg-indigo-50 text-indigo-700"
                                           : "border-gray-200 bg-white text-gray-600 hover:border-gray-400")

            a(href: filter_reserves_path(q: @q, from: @from, to: @to),
              class: filter_classes,
              data: { turbo_frame: "drawer-frame" }) do
              render UI::Icon.new(:filter, class: "w-3 h-3")
              plain "Filters"
              if filter_count > 0
                span(class: "inline-flex items-center justify-center w-4 h-4 rounded-full text-[10px] font-bold",
                     style: "background:#4f46e5;color:#fff") { plain filter_count.to_s }
              end
            end
          end
        end
      end

      def hold_row(h)
        state     = h["state"] || "pending"
        style     = STATE_STYLES[state] || { badge: STATUS_NEUTRAL, label: state.capitalize }
        cur       = h["currency"] || "GHS"
        pay_link  = h["payment_public_id"].present? ? payment_path(h["payment_public_id"]) : nil
        ref_label = h["payment_reference"].presence || short_public_id(h["payment_public_id"])

        tr(class: "border-b border-gray-50 last:border-0 hover:bg-gray-50/70 transition-colors") do
          td(class: "px-6 py-[14px]") do
            if pay_link
              a(href: pay_link, class: "group flex flex-col gap-[2px] no-underline") do
                span(class: "text-[12.5px] font-medium group-hover:underline",
                     style: "color:#{BRAND}") { plain ref_label }
                if h["payment_reference"].present?
                  span(class: "#{TYPE_CAPTION} text-gray-400") { plain short_public_id(h["payment_public_id"]) }
                end
              end
            else
              span(class: "font-mono text-[12px] text-gray-500") { plain ref_label }
            end
          end
          td(class: "px-6 py-[14px] text-right") do
            span(class: "text-[13px] font-semibold tabular-nums text-gray-900") { plain format_amount(h["amount"], cur) }
          end
          td(class: "px-6 py-[14px]") do
            span(class: "#{BADGE} #{style[:badge]}") { plain style[:label] }
          end
          td(class: "px-6 py-[14px]") do
            span(class: "text-[12.5px] text-gray-500") { plain format_date(h["held_at"]) }
          end
          td(class: "px-6 py-[14px]") do
            case state
            when "pending"
              rel = days_until(h["release_at"])
              div(class: "flex flex-col gap-[2px]") do
                span(class: "text-[12.5px] font-medium text-gray-700") { plain rel || format_date(h["release_at"]) }
                span(class: TYPE_CAPTION) { plain format_date(h["release_at"]) } if rel
              end
            when "released"
              div(class: "flex flex-col gap-[2px]") do
                span(class: "text-[12.5px] font-medium", style: "color:#{GREEN}") { plain "Released" }
                span(class: TYPE_CAPTION) { plain format_date(h["released_at"]) }
              end
            else
              div(class: "flex flex-col gap-[2px]") do
                span(class: "text-[12.5px] font-medium", style: "color:#{RED}") { plain "Drawn" }
                span(class: TYPE_CAPTION) { plain format_date(h["drawn_at"]) }
              end
            end
          end
        end
      end

      # ── Helpers ───────────────────────────────────────────────────────────────

      def format_amount(pence, currency)
        return "—" if pence.nil?
        format_money(pence.to_i, currency: currency)
      end

      def format_date(iso)
        return "—" if iso.nil?
        fmt_date(Time.parse(iso)) rescue "—"
      end

      def days_until(iso)
        return nil if iso.nil?
        delta = (Time.parse(iso).to_date - Date.current).to_i
        if delta < 0     then "Overdue"
        elsif delta == 0 then "Today"
        elsif delta == 1 then "Tomorrow"
        else                  "In #{delta} days"
        end
      rescue ArgumentError
        nil
      end

      def short_public_id(id)
        return "—" if id.blank?
        id.to_s.first(16) + "…"
      end

      def total_count
        @summary["pending_count"].to_i + @summary["released_count"].to_i + @summary["drawn_count"].to_i
      end

      def forecast_present?
        %w[next_30_days next_31_60_days next_61_90_days beyond_90_days].any? { |k| @forecast[k].to_i > 0 }
      end

      def page_params(page)
        { state: @state_filter, q: @q, from: @from, to: @to, page: page }.compact
      end
    end
  end
end
