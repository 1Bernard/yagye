# frozen_string_literal: true

module Dashboard
  class IndexView < ApplicationComponent
    include UI::Theme

    def initialize(volume:, tx_count:, success_rate:, pending_count:, failed_count:,
                   prev_volume: 0, prev_tx_count: 0, success_count: 0,
                   net_volume: nil, refunded_volume: 0, refunded_count: 0,
                   disputes_count: 0, kyb_pending_count: nil,
                   active_merchant_count: nil,
                   chart_dates: [], chart_values: [],
                   provider_data: [], method_data: [],
                   recent_payments: [],
                   fx_currency: "GHS", fx_rate: nil, fx_corridor: [],
                   is_ops: false, network_health: [],
                   upcoming_payout: nil, payout_balance: nil,
                   feed_stream_key: nil)
      @volume                = volume
      @net_volume            = net_volume.nil? ? volume : net_volume
      @refunded_volume       = refunded_volume.to_i
      @refunded_count        = refunded_count.to_i
      @prev_volume           = prev_volume.to_i
      @tx_count              = tx_count
      @prev_tx_count         = prev_tx_count.to_i
      @success_count         = success_count.to_i
      @success_rate          = success_rate
      @pending_count         = pending_count
      @failed_count          = failed_count
      @disputes_count        = disputes_count
      @kyb_pending_count     = kyb_pending_count
      @active_merchant_count = active_merchant_count
      @chart_dates           = chart_dates
      @chart_values          = chart_values
      @provider_data         = provider_data
      @method_data           = method_data
      @recent_payments       = recent_payments
      @fx_currency           = fx_currency || "GHS"
      @fx_rate               = fx_rate
      @fx_corridor           = fx_corridor
      @is_ops                = is_ops
      @network_health        = network_health
      @upcoming_payout       = upcoming_payout
      @payout_balance        = payout_balance
      @feed_stream_key       = feed_stream_key
    end

    def view_template
      render Layout::Shell.new(
        active_nav:  :dashboard,
        title:       "Dashboard",
        breadcrumbs: [ { label: "Dashboard" } ]
      ) do
        div(data: { controller: "dashboard-refresh",
                    dashboard_refresh_interval_value: "60" }) do
          refresh_bar
          network_health_bar
          kpi_row
          payout_balance_card
          upcoming_payout_card
          quick_actions_bar
          funnel_card
          chart_card
          breakdown_row
        end
      end
    end

    private

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # REFRESH BAR
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    def refresh_bar
      div(class: "flex items-center justify-between gap-3 mb-4") do
        div(class: "flex items-center gap-3") do
          fx_toggle
          fx_corridor_rates
        end

        div(class: "flex items-center gap-3") do
          span(class: TYPE_CAPTION) do
            plain "Updated "
            span(data: { dashboard_refresh_target: "timestamp" }) { plain "just now" }
            plain " · auto-refreshes every minute"
          end
          button(type: "button",
                 class: "flex items-center gap-1.5 #{TYPE_CAPTION} text-[#3D47F5] font-medium " \
                        "hover:opacity-70 transition-opacity border-0 bg-transparent cursor-pointer p-0",
                 data: { action: "click->dashboard-refresh#reload" }) do
            span(class: "flex w-[11px] h-[11px]") { render UI::Icon.new(:refresh, class: "w-full h-full") }
            plain "Refresh"
          end
        end
      end
    end

    def fx_corridor_rates
      return if @fx_corridor.blank?

      syms = { "USD" => "$", "EUR" => "€", "GBP" => "£" }
      rates_text = @fx_corridor.filter_map do |r|
        next if r[:rate].to_f.zero?
        inverse = (1.0 / r[:rate]).round(2)
        sym = syms.fetch(r[:currency], r[:currency])
        "1#{sym} = GHS #{sprintf('%.2f', inverse)}"
      end.join(" · ")

      return if rates_text.blank?

      span(class: "#{TYPE_CAPTION} hidden sm:inline") { plain rates_text }
    end

    def fx_toggle
      currencies = %w[GHS USD EUR GBP]
      div(class: "flex items-center gap-1 bg-gray-100 rounded-lg p-[3px]") do
        currencies.each do |cur|
          active    = cur == @fx_currency
          state_cls = active ? "bg-white text-gray-900 shadow-sm" : "text-gray-500 hover:text-gray-700"
          a(href: authenticated_root_path(fx_currency: cur),
            class: "px-3 py-[5px] rounded-md text-[11.5px] font-semibold transition-colors no-underline #{state_cls}") do
            plain cur
          end
        end
      end
    end

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # NETWORK HEALTH BAR
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    def network_health_bar
      return if @network_health.blank?

      total_lost = @network_health
                     .select { |n| n[:status].in?(%i[degraded disrupted]) }
                     .sum { |n| n[:failed_volume_mtd].to_i }

      div(class: "flex items-center gap-3 mb-4 px-4 py-2.5 bg-white border border-gray-100 rounded-xl") do
        span(class: "text-[11px] font-semibold text-gray-400 uppercase tracking-wide flex-shrink-0 mr-1") do
          plain "Network"
        end
        div(class: "flex items-center gap-2 flex-1 flex-wrap") do
          @network_health.each { |n| network_chip(n) }
        end
        span(class: TYPE_CAPTION) { plain "last 30 min" }
        if total_lost > 0
          span(class: "text-gray-200 flex-shrink-0") { plain "·" }
          lost_color = @network_health.any? { |n| n[:status] == :disrupted } ? RED : AMBER
          span(class: "text-[11.5px] font-semibold tabular-nums flex-shrink-0",
               style: "color:#{lost_color}") do
            plain "#{format_ghs(total_lost)} lost MTD"
          end
        end
      end
    end

    def network_chip(n)
      dot_color              = network_dot_color(n[:status])
      label, txt_col, bg_col = network_status_cfg(n[:status])

      div(class: "flex items-center gap-2 px-3 py-1.5 bg-gray-50 rounded-lg border border-gray-100") do
        span(class: "w-2 h-2 rounded-full flex-shrink-0", style: "background:#{dot_color}")
        span(class: "text-[12.5px] font-semibold text-gray-800") { plain n[:name] }
        if n[:rate]
          span(class: "text-[11.5px] tabular-nums font-medium text-gray-400") { plain "#{n[:rate]}%" }
        end
        span(class: "text-[10px] font-bold px-1.5 py-[2px] rounded-full ml-0.5",
             style: "color:#{txt_col};background:#{bg_col}") { plain label }
      end
    end

    def network_dot_color(status)
      case status
      when :healthy   then GREEN
      when :degraded  then AMBER
      when :disrupted then RED
      else                 "#9CA3AF"
      end
    end

    def network_status_cfg(status)
      case status
      when :healthy   then ["Healthy",   GREEN,     TINT_GREEN]
      when :degraded  then ["Degraded",  AMBER,     TINT_AMBER]
      when :disrupted then ["Disrupted", RED,       TINT_RED]
      else                 ["No data",   "#6B7280",  "#F3F4F6"]
      end
    end

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # KPI ROW
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    def kpi_row
      div(class: "grid grid-cols-2 lg:grid-cols-4 gap-4 mb-5") do
        kpi_card(
          label:   "Net Volume",
          value:   format_net_volume,
          icon:    :trending_up,
          color:   BRAND,
          tint:    TINT_BRAND,
          delta:   volume_delta,
          sub:     refund_sub_label || fx_volume_sub || prev_volume_label
        )
        kpi_card(
          label:   "Transactions",
          value:   number_with_delimiter(@tx_count),
          icon:    :layers,
          color:   PURPLE,
          tint:    TINT_PURPLE,
          delta:   tx_delta,
          sub:     failed_sub_label
        )
        kpi_card(
          label:   "Success Rate",
          value:   rate_label,
          icon:    :check_circle,
          color:   rate_color,
          tint:    rate_tint
        )
        if @active_merchant_count
          kpi_card(
            label:  "Active Merchants",
            value:  number_with_delimiter(@active_merchant_count),
            icon:   :building,
            color:  BRAND,
            tint:   TINT_BRAND,
            sub:    kyb_sub_label
          )
        else
          kpi_card(
            label:  "Pending",
            value:  number_with_delimiter(@pending_count),
            icon:   :clock,
            color:  AMBER,
            tint:   TINT_AMBER
          )
        end
      end
    end

    def kpi_card(label:, value:, icon:, color:, tint:, delta: nil, sub: nil)
      div(class: "bg-white border border-gray-100 rounded-2xl p-[22px]") do
        # Icon row + optional delta chip
        div(class: "flex items-start justify-between mb-4") do
          div(class: "w-9 h-9 rounded-xl flex items-center justify-center",
              style: "background:#{tint}") do
            span(class: "flex w-[17px] h-[17px]", style: "color:#{color}") do
              render UI::Icon.new(icon, class: "w-full h-full")
            end
          end
          if delta
            pos = delta.to_f >= 0
            span(class: "text-[11px] font-semibold px-[7px] py-[2px] rounded-full",
                 style: "color:#{pos ? GREEN : RED};background:#{pos ? TINT_GREEN : TINT_RED}") do
              plain "#{pos ? '↑' : '↓'} #{delta.abs}%"
            end
          end
        end

        p(class: TYPE_HEADING) { plain label }
        p(class: "#{TYPE_STAT} mt-2", style: "color:#{color}") { plain value }

        if sub
          p(class: "#{TYPE_CAPTION} mt-[10px] truncate") { plain sub }
        end
      end
    end

    def fx_volume_sub
      return nil if @fx_currency == "GHS" || @fx_rate.nil?

      rate       = @fx_rate[:rate].to_f
      return nil if rate.zero?

      converted  = (@net_volume.to_f / 100.0 * rate)
      sym        = { "USD" => "$", "EUR" => "€", "GBP" => "£" }.fetch(@fx_currency, @fx_currency)
      rate_label = sprintf("%.4f", rate).sub(/0+$/, "")
      "≈ #{sym}#{sprintf('%.2f', converted)} · at GHS #{rate_label}/#{@fx_currency}"
    end

    def prev_volume_label
      return nil if @prev_volume.zero?
      "vs #{format_money(@prev_volume)} last month"
    end

    def failed_sub_label
      return nil if @failed_count.to_i.zero?
      "#{number_with_delimiter(@failed_count)} failed this month"
    end

    def disputes_sub_label
      return nil if @disputes_count.to_i.zero?
      "#{number_with_delimiter(@disputes_count)} open dispute#{'s' if @disputes_count != 1}"
    end

    def kyb_sub_label
      return nil if @kyb_pending_count.to_i.zero?
      "#{number_with_delimiter(@kyb_pending_count)} KYB pending review"
    end

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # QUICK ACTIONS BAR
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    def quick_actions_bar
      div(class: "flex items-center gap-3 mb-5 flex-wrap") do
        if @is_ops
          quick_btn(icon: :shield,  label: "Review KYB",   href: kyb_reviews_path)
          quick_btn(icon: :flag,    label: "Disputes",      href: disputes_path)
          quick_btn(icon: :layers,  label: "Settlements",   href: settlements_path)
        else
          quick_btn(icon: :link,    label: "New payment link",   href: new_payment_link_path)
          quick_btn(icon: :users,   label: "Invite team member", href: new_team_user_path, data: { turbo_frame: "drawer-frame" })
          quick_btn(icon: :wallet,  label: "Request payout",     href: new_payout_request_path)
        end
      end
    end

    def quick_btn(icon:, label:, href:, data: {})
      a(href: href, data: data,
        class: "inline-flex items-center gap-2 px-4 py-[9px] border border-gray-200 rounded-xl " \
               "text-[13px] font-medium text-gray-600 bg-white no-underline flex-shrink-0 " \
               "hover:border-[#3D47F5] hover:text-[#3D47F5] transition-colors") do
        span(class: "flex w-[14px] h-[14px] flex-shrink-0") do
          render UI::Icon.new(icon, class: "w-full h-full")
        end
        plain label
      end
    end

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # UPCOMING PAYOUT CARD
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    def payout_balance_card
      return if @payout_balance.nil?

      pb = @payout_balance

      div(class: "bg-white border border-gray-100 rounded-2xl px-6 py-5 mb-5") do
        div(class: "flex items-start gap-6 flex-wrap") do
          # ── Accumulated balance ──────────────────────────────────────────────
          div(class: "flex-1 min-w-[160px]") do
            p(class: TYPE_CAPTION) { plain "Balance" }
            p(class: "text-[26px] font-extrabold tabular-nums tracking-tight text-gray-900 mt-[6px] leading-none") do
              plain format_money(pb[:balance], currency: pb[:currency])
            end
            p(class: "#{TYPE_CAPTION} mt-[6px]") do
              plain "#{number_with_delimiter(pb[:payment_count])} payment#{pb[:payment_count] == 1 ? '' : 's'} collected"
              if pb[:cycle_start]
                plain " since #{pb[:cycle_start].strftime('%-d %b')}"
              end
            end
          end

          # ── Divider ──────────────────────────────────────────────────────────
          div(class: "w-px self-stretch bg-gray-100 flex-shrink-0 hidden sm:block")

          # ── Next payout ──────────────────────────────────────────────────────
          div(class: "flex-1 min-w-[140px]") do
            p(class: TYPE_CAPTION) { plain "Next payout" }
            if pb[:next_payout_date]
              p(class: "text-[18px] font-bold text-gray-900 mt-[6px] leading-none") do
                plain pb[:next_payout_date].strftime("%a, %-d %b")
              end
              div(class: "flex items-center gap-2 mt-[8px] flex-wrap") do
                if pb[:next_payout_amount]
                  span(class: "text-[12.5px] font-semibold text-gray-700") do
                    plain format_money(pb[:next_payout_amount], currency: pb[:currency])
                  end
                end
                if pb[:next_payout_state]
                  payout_state_chip(pb[:next_payout_state])
                end
              end
            else
              p(class: "text-[15px] text-gray-400 mt-[6px]") { plain "None scheduled" }
            end
          end

          # ── View link ────────────────────────────────────────────────────────
          a(href: "#",
            class: "self-center flex items-center gap-1 text-[12px] font-semibold no-underline flex-shrink-0 hover:opacity-70 transition-opacity",
            style: "color:#{BRAND}") do
            plain "View payouts"
            span(class: "flex w-[11px] h-[11px]") { render UI::Icon.new(:arrow_right, class: "w-full h-full") }
          end
        end
      end
    end

    def upcoming_payout_card
      return if @upcoming_payout.nil?
      return if @upcoming_payout[:kind] == :merchant  # balance_card covers the merchant view

      pu = @upcoming_payout

      div(class: "flex items-center gap-4 mb-5 px-4 py-3 bg-white border border-gray-100 rounded-xl") do
        div(class: "w-8 h-8 rounded-lg flex items-center justify-center flex-shrink-0",
            style: "background:#{TINT_BRAND}") do
          span(class: "flex w-[15px] h-[15px]", style: "color:#{BRAND}") do
            render UI::Icon.new(:calendar, class: "w-full h-full")
          end
        end

        if pu[:kind] == :ops
          div(class: "flex-1 flex items-center gap-3 min-w-0 flex-wrap") do
            span(class: "text-[12.5px] font-semibold text-gray-800 flex-shrink-0") { plain "Upcoming Payouts" }
            span(class: "text-[12px] text-gray-500 flex-shrink-0") do
              plain "#{number_with_delimiter(pu[:count])} scheduled · #{format_money(pu[:total], currency: pu[:currency])} total"
            end
            payout_date_chip(pu[:next_date], pu[:days_until])
          end
        else
          div(class: "flex-1 flex items-center gap-3 min-w-0 flex-wrap") do
            span(class: "text-[12.5px] font-semibold text-gray-800 flex-shrink-0") { plain "Next Payout" }
            span(class: "text-[13px] font-bold tabular-nums text-gray-900 flex-shrink-0") do
              plain format_money(pu[:amount], currency: pu[:currency])
            end
            payout_date_chip(pu[:date], pu[:days_until])
            payout_state_chip(pu[:state])
          end
        end

        a(href: "#",
          class: "flex items-center gap-1 text-[12px] font-semibold flex-shrink-0 no-underline hover:opacity-70 transition-opacity",
          style: "color:#{BRAND}") do
          plain pu[:kind] == :ops ? "View all" : "View payouts"
          span(class: "flex w-[11px] h-[11px]") { render UI::Icon.new(:arrow_right, class: "w-full h-full") }
        end
      end
    end

    def payout_date_chip(date, days_until)
      days_label = case days_until
                   when 0 then "today"
                   when 1 then "tomorrow"
                   else        "in #{days_until} days"
                   end

      div(class: "flex items-center gap-1.5 px-2.5 py-1 bg-gray-50 rounded-lg border border-gray-100 flex-shrink-0") do
        span(class: "text-[12px] font-medium text-gray-700") { plain date.strftime("%a %-d %b") }
        span(class: "text-[11px] text-gray-400") { plain "· #{days_label}" }
      end
    end

    def payout_state_chip(state)
      color, bg = case state
                  when "scheduled"               then [BRAND, TINT_BRAND]
                  when "submitted"               then [GREEN, TINT_GREEN]
                  when "validating", "reserving" then [AMBER, TINT_AMBER]
                  else                                ["#6B7280", "#F3F4F6"]
                  end
      span(class: "text-[10px] font-bold px-[6px] py-[2px] rounded-full capitalize flex-shrink-0",
           style: "color:#{color};background:#{bg}") { plain state.capitalize }
    end

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # CONVERSION FUNNEL
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    def funnel_card
      return if @tx_count.to_i.zero?

      dropped     = @tx_count - @success_count - @pending_count
      paid_pct    = pct_of(@tx_count, @success_count)
      failed_pct  = pct_of(@tx_count, dropped)
      pending_pct = pct_of(@tx_count, @pending_count)

      div(class: "bg-white border border-gray-100 rounded-2xl px-6 py-5 mb-5") do
        # ── Header ────────────────────────────────────────────────────────────
        div(class: "flex items-start justify-between mb-1") do
          div do
            p(class: TYPE_TITLE) { plain "Payment Funnel" }
            p(class: "#{TYPE_CAPTION} mt-1") do
              plain "#{number_with_delimiter(@tx_count)} payment attempts this month"
            end
          end
          div(class: "flex items-baseline gap-[6px]") do
            span(class: "text-[30px] font-extrabold tracking-[-0.03em] tabular-nums leading-none",
                 style: "color:#{rate_color}") { plain "#{@success_rate || 0}%" }
            span(class: TYPE_CAPTION) { plain "success rate" }
          end
        end

        # ── Stacked bar ───────────────────────────────────────────────────────
        div(class: "flex gap-1 my-5", style: "height:8px") do
          funnel_bar_segment(paid_pct,    GREEN)
          funnel_bar_segment(failed_pct,  RED)
          funnel_bar_segment(pending_pct, AMBER)
        end

        # ── Stat tiles ────────────────────────────────────────────────────────
        div(class: "flex items-stretch gap-3") do
          funnel_tile(@success_count, "Paid",              paid_pct,    GREEN,  "#f0fdf4")
          funnel_tile(dropped,        "Failed",            failed_pct,  RED,    "#fef2f2")
          funnel_tile(@pending_count, "Pending",            pending_pct, AMBER,  "#fffbeb")
        end
      end
    end

    def funnel_bar_segment(pct, color)
      return if pct.to_f <= 0
      div(style: "flex:#{pct};background:#{color};border-radius:4px;transition:flex 0.4s ease")
    end

    def funnel_tile(count, label, pct, color, bg)
      div(class: "flex-1 rounded-xl px-4 py-3", style: "background:#{bg}") do
        p(class: "text-[22px] font-extrabold tabular-nums tracking-tight leading-none mb-1",
          style: "color:#{color}") { plain number_with_delimiter(count) }
        p(class: TYPE_BODY_MD) { plain label }
        p(class: "text-[11px] font-semibold mt-0.5 text-gray-400") do
          plain "#{pct}% of total"
        end
      end
    end

    def pct_of(total, part)
      return 0 if total.to_i.zero?
      (part.to_f / total * 100).round(1)
    end

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # VOLUME CHART — full width, large, period-toggleable
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    def chart_card
      div(class: "bg-white border border-gray-100 rounded-2xl mb-5") do
        # Header
        div(class: "flex items-center justify-between px-6 pt-5 pb-0") do
          div do
            p(class: TYPE_TITLE) { plain "Transaction Volume" }
            p(class: "#{TYPE_CAPTION} mt-1") { plain "Daily paid volume · GHS" }
          end
          div(class: "flex items-center gap-1 p-1 bg-gray-50 rounded-xl",
              data: { controller: "period-toggle" }) do
            period_btn("7D",  "7d",  false)
            period_btn("30D", "30d", true)
            period_btn("3M",  "90d", false)
          end
        end

        # Charts
        div(class: "px-6 pt-4 pb-5") do
          chart_wrap("7d",  false) { render UI::Chart::Line.new(labels: @chart_dates.last(7),  data: @chart_values.last(7),  dataset_label: "Volume", area: true, height: 300) }
          chart_wrap("30d", true)  { render UI::Chart::Line.new(labels: @chart_dates.last(30), data: @chart_values.last(30), dataset_label: "Volume", area: true, height: 300) }
          chart_wrap("90d", false) { render UI::Chart::Line.new(labels: @chart_dates,          data: @chart_values,          dataset_label: "Volume", area: true, height: 300) }
        end
      end
    end

    def chart_wrap(period, visible, &)
      div(data: { period_chart: period }, style: visible ? "" : "display:none", &)
    end

    def period_btn(label, period, active)
      cls = active \
        ? "text-[11.5px] font-semibold px-3 py-1.5 rounded-lg text-white bg-[#3D47F5] cursor-pointer border-0" \
        : "text-[11.5px] font-medium px-3 py-1.5 rounded-lg text-gray-500 hover:text-gray-700 cursor-pointer border-0 bg-transparent"
      button(type: "button", class: cls,
             data: { period_btn: period, action: "click->period-toggle#switch" }) { plain label }
    end

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # BREAKDOWN ROW — 3 columns, each a card
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    def breakdown_row
      div(class: "grid gap-4 #{ @active_merchant_count ? 'grid-cols-3' : 'grid-cols-3' }") do
        provider_split_card
        method_split_card
        if @active_merchant_count
          review_card
        else
          activity_card
        end
      end
    end

    # ── Provider split ────────────────────────────────────────────────────────

    def provider_split_card
      div(class: "bg-white border border-gray-100 rounded-2xl px-5 pt-5 pb-5") do
        card_header("Provider Split", "Volume share by rail (MTD)")

        if @provider_data.empty?
          empty_state("No transaction data yet")
        else
          total = @provider_data.sum { |p| p[:amount] }
          render UI::Chart::Pie.new(
            labels:          @provider_data.map { |p| p[:name] },
            data:            @provider_data.map { |p| p[:amount] / 100.0 },
            colors:          @provider_data.map { |p| p[:color] },
            center_label:    format_money(total),
            center_sublabel: "total volume",
            height:          170
          )
          div(class: "mt-4 flex flex-col gap-[2px]") do
            @provider_data.each { |p| legend_row(p) }
          end
          if @is_ops
            p(class: "text-[10.5px] text-gray-400 mt-3 text-right") { plain "Click a rail to see merchant breakdown" }
          end
        end
      end
    end

    # ── Method split ──────────────────────────────────────────────────────────

    def method_split_card
      div(class: "bg-white border border-gray-100 rounded-2xl px-5 pt-5 pb-5") do
        card_header("Payment Methods", "Breakdown by method (MTD)")

        if @method_data.empty?
          empty_state("No transaction data yet")
        else
          div(class: "mt-2 flex flex-col gap-4") do
            @method_data.each { |m| method_bar_row(m) }
          end
        end
      end
    end

    def method_bar_row(item)
      div do
        div(class: "flex items-center justify-between mb-1.5") do
          div(class: "flex items-center gap-2") do
            span(class: "w-2 h-2 rounded-full", style: "background:#{item[:color]}")
            span(class: TYPE_BODY_MD) { plain item[:name] }
          end
          div(class: "flex items-center gap-3") do
            span(class: "#{TYPE_CAPTION} font-semibold") { plain "#{item[:pct]}%" }
            span(class: "#{TYPE_MONO} text-[12px]")      { plain format_money(item[:amount]) }
          end
        end
        # Progress bar
        div(class: "w-full bg-gray-100 rounded-full h-1.5") do
          div(class: "h-1.5 rounded-full", style: "width:#{item[:pct]}%;background:#{item[:color]}")
        end
      end
    end

    # ── Review card (ops only) ────────────────────────────────────────────────

    def review_card
      items = review_items
      div(class: "bg-white border border-gray-100 rounded-2xl px-5 pt-5 pb-5") do
        card_header("Needs Review", "Items requiring action")

        if items.empty?
          div(class: "mt-4 flex flex-col items-center gap-2 py-6 text-center") do
            div(class: "w-9 h-9 rounded-xl flex items-center justify-center mb-1",
                style: "background:#{TINT_GREEN}") do
              span(class: "flex w-[17px] h-[17px]", style: "color:#{GREEN}") do
                render UI::Icon.new(:check_circle, class: "w-full h-full")
              end
            end
            p(class: TYPE_BODY_MD) { plain "All clear" }
            p(class: TYPE_CAPTION) { plain "No items need attention right now." }
          end
        else
          div(class: "mt-4 flex flex-col divide-y divide-gray-50") do
            items.each { |item| review_row(item) }
          end
        end
      end
    end

    def review_items
      [].tap do |list|
        list << { label: "Failed payments",  count: @failed_count,      color: RED,   tint: TINT_RED,   icon: :alert_circle, href: payments_path(status: "failed") } if @failed_count.to_i > 0
        list << { label: "Open disputes",    count: @disputes_count,    color: RED,   tint: TINT_RED,   icon: :flag,         href: "#" }                              if @disputes_count.to_i > 0
        list << { label: "Pending payments", count: @pending_count,     color: AMBER, tint: TINT_AMBER, icon: :clock,        href: payments_path(status: "processing") } if @pending_count.to_i > 0
        list << { label: "KYB under review", count: @kyb_pending_count, color: TEAL,  tint: TINT_TEAL,  icon: :shield,       href: "#" }                              if @kyb_pending_count.to_i > 0
      end
    end

    def review_row(item)
      a(href: item[:href],
        class: "flex items-center gap-3 py-3 hover:bg-gray-50 -mx-5 px-5 rounded-xl transition-colors no-underline") do
        div(class: "w-8 h-8 rounded-lg flex items-center justify-center flex-shrink-0",
            style: "background:#{item[:tint]}") do
          span(class: "flex w-[14px] h-[14px]", style: "color:#{item[:color]}") do
            render UI::Icon.new(item[:icon], class: "w-full h-full")
          end
        end
        div(class: "flex-1 min-w-0") do
          p(class: TYPE_BODY_MD) { plain item[:label] }
        end
        span(class: "text-[13px] font-bold tabular-nums", style: "color:#{item[:color]}") do
          plain number_with_delimiter(item[:count])
        end
        span(class: "flex w-[13px] h-[13px] text-gray-300 flex-shrink-0") do
          render UI::Icon.new(:chev_right, class: "w-full h-full")
        end
      end
    end

    # ── Activity feed (merchant only) ─────────────────────────────────────────

    def activity_card
      div(class: "bg-white border border-gray-100 rounded-2xl overflow-hidden") do
        raw safe(turbo_stream_from(@feed_stream_key)) if @feed_stream_key

        div(class: "flex items-center justify-between px-5 pt-5 pb-0") do
          div do
            p(class: TYPE_TITLE) { plain "Latest Activity" }
            p(class: "#{TYPE_CAPTION} mt-1") { plain "Your most recent transactions" }
          end
          render UI::Button.new(variant: :ghost, href: payments_path) do
            plain "See all"
            span(class: "flex w-[12px] h-[12px]") { render UI::Icon.new(:arrow_right, class: "w-full h-full") }
          end
        end

        if @recent_payments.empty?
          div(class: "flex flex-col items-center gap-2 py-10 text-center px-5",
              id: "payment-feed-empty") do
            p(class: TYPE_BODY_MD) { plain "No payments yet" }
            p(class: TYPE_CAPTION) { plain "Transactions will appear here." }
          end
        end

        div(id: "payment-feed", class: "#{'mt-3 ' unless @recent_payments.empty?}divide-y divide-gray-50",
            data: { controller: "payment-feed", payment_feed_max_value: "6" }) do
          @recent_payments.first(6).each { |pay| feed_row(pay) }
        end
      end
    end

    def feed_row(pay)
      render Dashboard::FeedRowComponent.new(payment: pay)
    end

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # SHARED PRIMITIVES
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    def card_header(title, subtitle)
      div(class: "mb-4") do
        p(class: TYPE_TITLE) { plain title }
        p(class: "#{TYPE_CAPTION} mt-[3px]") { plain subtitle }
      end
    end

    def legend_row(item)
      base_cls = "flex items-center justify-between"
      if @is_ops
        a(href:  dashboard_provider_split_path(provider_code: item[:key]),
          class: "#{base_cls} rounded-lg px-2 py-1 -mx-2 hover:bg-gray-50 transition-colors cursor-pointer no-underline group",
          data:  { turbo_frame: "drawer-frame" }) do
          legend_row_inner(item, show_chevron: true)
        end
      else
        div(class: base_cls) { legend_row_inner(item) }
      end
    end

    def legend_row_inner(item, show_chevron: false)
      div(class: "flex items-center gap-2 min-w-0") do
        span(class: "w-2 h-2 rounded-full flex-shrink-0", style: "background:#{item[:color]}")
        span(class: "#{TYPE_CAPTION} truncate") { plain item[:name] }
      end
      div(class: "flex items-center gap-2 flex-shrink-0") do
        span(class: "text-[11.5px] font-semibold text-gray-400") { plain "#{item[:pct]}%" }
        span(class: "#{TYPE_MONO} text-[11.5px]")                { plain format_money(item[:amount]) }
        if show_chevron
          span(class: "w-3 h-3 text-gray-300 group-hover:text-gray-500 transition-colors ml-1 flex-shrink-0") do
            render UI::Icon.new(:chev, class: "w-full h-full")
          end
        end
      end
    end

    def empty_state(message)
      div(class: "flex items-center justify-center py-10") do
        p(class: TYPE_CAPTION) { plain message }
      end
    end

    # ── Value helpers ─────────────────────────────────────────────────────────

    def format_volume     = format_money(@volume)
    def format_net_volume = format_money(@net_volume)
    def rate_label        = @success_rate ? "#{@success_rate}%" : "—"

    def refund_sub_label
      return nil if @refunded_count.zero?
      gross_str = format_money(@volume)
      n         = @refunded_count
      "#{gross_str} gross · #{n} refund#{n == 1 ? '' : 's'}"
    end

    def rate_color
      return SUBTLE_TEXT unless @success_rate
      @success_rate >= 90 ? GREEN : @success_rate >= 75 ? AMBER : RED
    end

    def rate_tint
      return TINT_GRAY unless @success_rate
      @success_rate >= 90 ? TINT_GREEN : @success_rate >= 75 ? TINT_AMBER : TINT_RED
    end

    def volume_delta
      return nil if @prev_volume.zero?
      ((@volume - @prev_volume).to_f / @prev_volume * 100).round(1)
    end

    def tx_delta
      return nil if @prev_tx_count.zero?
      ((@tx_count - @prev_tx_count).to_f / @prev_tx_count * 100).round(1)
    end
  end
end
