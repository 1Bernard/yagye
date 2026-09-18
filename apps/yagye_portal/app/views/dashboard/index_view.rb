# frozen_string_literal: true

module Dashboard
  class IndexView < ApplicationComponent
    include UI::Theme

    def initialize(volume:, tx_count:, success_rate:, pending_count:, failed_count:,
                   prev_volume: 0, prev_tx_count: 0, success_count: 0,
                   disputes_count: 0, kyb_pending_count: nil,
                   active_merchant_count: nil,
                   chart_dates: [], chart_values: [],
                   provider_data: [], method_data: [],
                   recent_payments: [],
                   fx_currency: "GHS", fx_rate: nil)
      @volume                = volume
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
          kpi_row
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
        fx_toggle

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
    # KPI ROW
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    def kpi_row
      div(class: "grid grid-cols-2 lg:grid-cols-4 gap-4 mb-5") do
        kpi_card(
          label:   "Volume",
          value:   format_volume,
          icon:    :trending_up,
          color:   BRAND,
          tint:    TINT_BRAND,
          delta:   volume_delta,
          sub:     fx_volume_sub || prev_volume_label
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

      rate       = @fx_rate["rate"].to_f
      return nil if rate.zero?

      converted  = (@volume.to_f / 100.0 * rate)
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
        p(class: "text-[11px] font-semibold mt-0.5", style: "color:#{color};opacity:0.7") do
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
          div(class: "mt-4 flex flex-col gap-3") do
            @provider_data.each { |p| legend_row(p) }
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
          div(class: "flex flex-col items-center gap-2 py-10 text-center px-5") do
            p(class: TYPE_BODY_MD) { plain "No payments yet" }
            p(class: TYPE_CAPTION) { plain "Transactions will appear here." }
          end
        else
          div(class: "mt-3 divide-y divide-gray-50") do
            @recent_payments.first(6).each { |pay| feed_row(pay) }
          end
        end
      end
    end

    def feed_row(pay)
      dot_color = case pay.status
                  when "paid"   then GREEN
                  when "failed" then RED
                  else               AMBER
                  end

      div(class: "flex items-center gap-3 px-5 py-[10px] hover:bg-gray-50 transition-colors") do
        span(class: "w-[7px] h-[7px] rounded-full flex-shrink-0 mt-[1px]",
             style: "background:#{dot_color}")
        div(class: "flex-1 min-w-0") do
          p(class: "#{TYPE_MONO} truncate leading-snug") { plain pay.reference.to_s }
          p(class: "#{TYPE_CAPTION} mt-[1px]")           { plain pay.masked_msisdn }
        end
        div(class: "text-right flex-shrink-0") do
          p(class: "text-[13px] font-semibold text-gray-900 tabular-nums leading-snug") do
            plain pay.formatted_amount
          end
          p(class: TYPE_CAPTION) { plain time_ago(pay.created_at) }
        end
      end
    end

    def time_ago(time)
      diff = Time.current - time
      case diff
      when 0..59        then "just now"
      when 60..3599     then "#{(diff / 60).to_i}m ago"
      when 3600..86_399 then "#{(diff / 3600).to_i}h ago"
      else                   time.strftime("%-d %b")
      end
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
      div(class: "flex items-center justify-between") do
        div(class: "flex items-center gap-2 min-w-0") do
          span(class: "w-2 h-2 rounded-full flex-shrink-0", style: "background:#{item[:color]}")
          span(class: "#{TYPE_CAPTION} truncate") { plain item[:name] }
        end
        div(class: "flex items-center gap-2 flex-shrink-0") do
          span(class: "text-[11.5px] font-semibold text-gray-400") { plain "#{item[:pct]}%" }
          span(class: "#{TYPE_MONO} text-[11.5px]")                { plain format_money(item[:amount]) }
        end
      end
    end

    def empty_state(message)
      div(class: "flex items-center justify-center py-10") do
        p(class: TYPE_CAPTION) { plain message }
      end
    end

    # ── Value helpers ─────────────────────────────────────────────────────────

    def format_volume = format_money(@volume)
    def rate_label    = @success_rate ? "#{@success_rate}%" : "—"

    def rate_color
      return SUBTLE_TEXT unless @success_rate
      @success_rate >= 95 ? GREEN : @success_rate >= 80 ? AMBER : RED
    end

    def rate_tint
      return TINT_GRAY unless @success_rate
      @success_rate >= 95 ? TINT_GREEN : @success_rate >= 80 ? TINT_AMBER : TINT_RED
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
