# frozen_string_literal: true

module Dashboard
  class IndexView < ApplicationComponent
    include UI::Theme

    BRAND  = "#3D47F5"
    TEAL   = "#0d9488"
    GREEN  = "#16a34a"
    AMBER  = "#d97706"
    RED    = "#dc2626"
    PURPLE = "#6d28d9"

    def initialize(volume_cents:, tx_count:, success_rate:, pending_count:, failed_count:,
                   prev_volume_cents: 0, prev_tx_count: 0,
                   disputes_count: 0, kyb_pending_count: nil,
                   chart_dates: [], chart_values: [],
                   provider_data: [], recent_payments: [])
      @volume_cents      = volume_cents
      @prev_volume_cents = prev_volume_cents.to_i
      @tx_count          = tx_count
      @prev_tx_count     = prev_tx_count.to_i
      @success_rate      = success_rate
      @pending_count     = pending_count
      @failed_count      = failed_count
      @disputes_count    = disputes_count
      @kyb_pending_count = kyb_pending_count  # nil for merchant users
      @chart_dates       = chart_dates
      @chart_values      = chart_values
      @provider_data     = provider_data
      @recent_payments   = recent_payments
    end

    def view_template
      render Layout::Shell.new(
        active_nav: :dashboard,
        title: "Dashboard",
        breadcrumbs: [ { label: "Dashboard" } ]
      ) do
        stat_grid
        charts_row
        recent_table
      end
    end

    private

    # ── Stat grid ─────────────────────────────────────────────────────────────
    # 6 cards: volume, transactions, success rate, pending, failed/KYB (role-split), disputes

    def stat_grid
      div(style: "display:grid;grid-template-columns:repeat(3,1fr);gap:16px;margin-bottom:20px") do
        stat_card(
          label: "Volume (MTD)",
          value: format_volume,
          icon:  :trending_up,
          color: BRAND,
          tint:  "rgba(61,71,245,0.08)",
          delta: volume_delta
        )
        stat_card(
          label: "Transactions (MTD)",
          value: fmt(@tx_count),
          icon:  :layers,
          color: PURPLE,
          tint:  "rgba(109,40,217,0.08)",
          delta: tx_delta
        )
        stat_card(
          label: "Success Rate",
          value: rate_label,
          icon:  :check_circle,
          color: rate_color,
          tint:  rate_tint,
          delta: nil
        )
        stat_card(
          label: "Pending",
          value: fmt(@pending_count),
          icon:  :clock,
          color: AMBER,
          tint:  "rgba(217,119,6,0.08)",
          delta: nil
        )
        # Role-split: ops see KYB queue, merchants see their own failures
        if @kyb_pending_count
          stat_card(
            label: "KYB Under Review",
            value: fmt(@kyb_pending_count),
            icon:  :shield,
            color: TEAL,
            tint:  "rgba(13,148,136,0.08)",
            delta: nil
          )
        else
          stat_card(
            label: "Failed (MTD)",
            value: fmt(@failed_count),
            icon:  :alert_circle,
            color: RED,
            tint:  "rgba(220,38,38,0.08)",
            delta: nil
          )
        end
        stat_card(
          label: "Open Disputes",
          value: @disputes_count.zero? ? "0" : fmt(@disputes_count),
          icon:  :flag,
          color: RED,
          tint:  "rgba(220,38,38,0.08)",
          delta: nil
        )
      end
    end

    def stat_card(label:, value:, icon:, color:, tint:, delta:)
      div(class: "dash-stat-card",
          style: "background:#fff;border:1px solid #{BORDER};border-radius:16px;padding:20px 22px") do
        div(style: "display:flex;align-items:flex-start;justify-content:space-between;margin-bottom:14px") do
          div(style: "width:36px;height:36px;border-radius:10px;background:#{tint};" \
                     "display:flex;align-items:center;justify-content:center;flex-shrink:0") do
            span(style: "color:#{color};display:flex;width:17px;height:17px") do
              render UI::Icon.new(icon, class: "w-full h-full")
            end
          end
          if delta
            positive = delta >= 0
            delta_color = positive ? GREEN : RED
            delta_bg    = positive ? "rgba(22,163,74,0.08)" : "rgba(220,38,38,0.08)"
            span(style: "font-size:11px;font-weight:600;color:#{delta_color};" \
                        "padding:2px 7px;border-radius:20px;background:#{delta_bg}") do
              plain "#{positive ? '+' : ''}#{delta}%"
            end
          end
        end
        p(style: "#{TYPE_HEADING};margin-bottom:8px") { plain label }
        p(style: "font-size:26px;font-weight:700;letter-spacing:-0.03em;color:#{INK};" \
                 "#{TYPE_NUM};line-height:1") { plain value }
      end
    end

    # ── Charts row ────────────────────────────────────────────────────────────

    def charts_row
      div(style: "display:grid;grid-template-columns:2fr 1fr;gap:16px;margin-bottom:20px") do
        volume_chart_card
        provider_split_card
      end
    end

    def volume_chart_card
      has_data = @chart_values.any?(&:positive?)

      div(style: "background:#fff;border:1px solid #{BORDER};border-radius:16px;overflow:hidden") do
        div(style: "display:flex;align-items:center;justify-content:space-between;padding:18px 22px 0") do
          div do
            p(style: TYPE_TITLE) { plain "Transaction Volume" }
            p(style: "#{TYPE_CAPTION};margin-top:3px") { plain "Daily paid volume · last 30 days" }
          end
          div(style: "display:flex;align-items:center;gap:4px") do
            period_btn("7D", false)
            period_btn("30D", true)
            period_btn("3M", false)
          end
        end
        div(style: "padding:16px 22px 20px") do
          if has_data
            div(style: "height:220px",
                data: { controller: "echarts", echarts_option_value: volume_chart_json }) do
              p(style: "text-align:center;color:#d1d5db;font-size:13px;padding-top:90px") { plain "Loading…" }
            end
          else
            chart_empty(:line_chart, "No transactions yet",
                        "Volume will appear here once payments start.")
          end
        end
      end
    end

    def provider_split_card
      has_providers = @provider_data.any?

      div(style: "background:#fff;border:1px solid #{BORDER};border-radius:16px;padding:18px 22px") do
        p(style: "#{TYPE_TITLE};margin-bottom:3px") { plain "Provider Split" }
        p(style: "#{TYPE_CAPTION};margin-bottom:16px") { plain "Volume by provider (MTD)" }

        if has_providers
          div(style: "height:168px",
              data: { controller: "echarts", echarts_option_value: donut_chart_json }) do
            p(style: "text-align:center;color:#d1d5db;font-size:13px;padding-top:66px") { plain "Loading…" }
          end
          div(style: "margin-top:16px;display:flex;flex-direction:column;gap:10px") do
            @provider_data.each { |p| provider_row(p) }
          end
        else
          chart_empty(:bar_chart, "No data yet", "Provider breakdown will appear here.")
        end
      end
    end

    def period_btn(label, active)
      s = if active
            "font-size:11.5px;font-weight:600;padding:4px 10px;border-radius:6px;" \
            "background:#{BRAND};color:#fff;cursor:pointer;border:none"
      else
            "font-size:11.5px;font-weight:500;padding:4px 10px;border-radius:6px;" \
            "background:transparent;color:#9ca3af;cursor:pointer;border:none"
      end
      button(type: "button", style: s) { plain label }
    end

    def provider_row(prov)
      div(style: "display:flex;align-items:center;justify-content:space-between") do
        div(style: "display:flex;align-items:center;gap:8px") do
          span(style: "width:8px;height:8px;border-radius:50%;background:#{prov[:color]};flex-shrink:0")
          span(style: "#{TYPE_CAPTION}") { plain prov[:name] }
        end
        div(style: "display:flex;align-items:center;gap:8px") do
          span(style: "#{TYPE_CAPTION};color:#{SUBTLE_TEXT}") { plain "#{prov[:pct]}%" }
          span(style: "#{TYPE_MONO}") do
            plain "GHS #{fmt_decimal(prov[:amount_cents] / 100.0)}"
          end
        end
      end
    end

    def chart_empty(icon_name, title, body)
      div(style: "height:168px;display:flex;flex-direction:column;align-items:center;" \
                 "justify-content:center;gap:8px") do
        div(style: "width:40px;height:40px;border-radius:12px;background:#f9fafb;" \
                   "display:flex;align-items:center;justify-content:center;margin-bottom:2px") do
          span(style: "color:#d1d5db;display:flex;width:20px;height:20px") do
            render UI::Icon.new(icon_name, class: "w-full h-full")
          end
        end
        p(style: "font-size:13px;font-weight:500;color:#6b7280") { plain title }
        p(style: "font-size:12px;color:#9ca3af;text-align:center;max-width:180px") { plain body }
      end
    end

    # ── Recent payments table ─────────────────────────────────────────────────

    def recent_table
      div(style: "background:#fff;border:1px solid #{BORDER};border-radius:16px;overflow:hidden") do
        table_action_bar
        if @recent_payments.empty?
          table_empty_state
        else
          div(style: "overflow-x:auto") do
            table(style: "width:100%;border-collapse:collapse;min-width:780px") do
              table_head
              tbody { @recent_payments.each { |pay| table_row(pay) } }
            end
          end
          table_footer
        end
      end
    end

    def table_action_bar
      div(style: "display:flex;align-items:center;justify-content:space-between;" \
                 "padding:14px 20px;border-bottom:1px solid #{BORDER}") do
        div(style: "display:flex;align-items:center;gap:10px") do
          p(style: TYPE_TITLE) { plain "Recent Payments" }
          unless @recent_payments.empty?
            span(style: "font-size:11px;font-weight:600;padding:2px 8px;" \
                        "background:#{SURFACE};border-radius:20px;color:#{MUTED_TEXT}") do
              plain "Last #{@recent_payments.size}"
            end
          end
        end
        div(style: "display:flex;align-items:center;gap:8px") do
          div(style: "display:flex;align-items:center;gap:8px;padding:7px 12px;" \
                     "border:1px solid #{BORDER_MED};border-radius:9px;min-width:176px;cursor:text") do
            span(style: "color:#{SUBTLE_TEXT};display:flex;width:13px;height:13px;flex-shrink:0") do
              render UI::Icon.new(:search, class: "w-full h-full")
            end
            span(style: "#{TYPE_CAPTION};color:#{SUBTLE_TEXT}") { plain "Search payments…" }
          end
          ghost_btn(:filter, "Filter")
          ghost_btn(:download, "Export")
          a(href: payments_path,
            style: "display:inline-flex;align-items:center;gap:6px;padding:7px 14px;" \
                   "background:#{BRAND};border-radius:9px;font-size:12.5px;font-weight:600;" \
                   "color:#fff;text-decoration:none;white-space:nowrap") do
            plain "View all"
            span(style: "display:flex;width:13px;height:13px") do
              render UI::Icon.new(:arrow_right, class: "w-full h-full")
            end
          end
        end
      end
    end

    def ghost_btn(icon_name, label)
      button(type: "button",
             style: "display:inline-flex;align-items:center;gap:6px;padding:7px 12px;" \
                    "border:1px solid #{BORDER_MED};border-radius:9px;font-size:12.5px;" \
                    "font-weight:500;color:#{BODY_TEXT};background:#fff;cursor:pointer;white-space:nowrap") do
        span(style: "display:flex;width:13px;height:13px") do
          render UI::Icon.new(icon_name, class: "w-full h-full")
        end
        plain label
      end
    end

    def table_head
      thead do
        tr(style: "border-bottom:1px solid #{BORDER}") do
          th(style: "padding:10px 12px 10px 20px;width:36px") do
            input(type: "checkbox",
                  style: "width:14px;height:14px;border-radius:3px;cursor:pointer;accent-color:#{BRAND}")
          end
          th_col("Reference")
          th_col("Customer")
          th_col("Amount")
          th_col("Method")
          th_col("Provider")
          th_col("Status")
          th_col("Date")
          th(style: "padding:10px 20px 10px 14px;width:40px")
        end
      end
    end

    def th_col(label)
      th(style: "padding:10px 14px;text-align:left;white-space:nowrap;cursor:pointer") do
        div(style: "display:inline-flex;align-items:center;gap:4px") do
          span(style: TYPE_HEADING) { plain label }
          span(style: "color:#{FAINT_TEXT};font-size:10px") { plain "↕" }
        end
      end
    end

    def table_row(pay)
      tr(class: "dash-tr", style: "border-bottom:1px solid #{BORDER};cursor:pointer") do
        td(style: "padding:12px 12px 12px 20px") do
          input(type: "checkbox",
                style: "width:14px;height:14px;border-radius:3px;cursor:pointer;accent-color:#{BRAND}")
        end
        td(style: "padding:12px 14px") do
          span(style: TYPE_MONO) { plain pay.reference.to_s }
        end
        td(style: "padding:12px 14px") do
          span(style: TYPE_CAPTION) { plain pay.masked_msisdn }
        end
        td(style: "padding:12px 14px") do
          span(style: "font-size:13px;font-weight:600;color:#{INK};#{TYPE_NUM}") do
            plain pay.formatted_amount
          end
        end
        td(style: "padding:12px 14px") do
          method_badge(pay.try(:payment_method).to_s)
        end
        td(style: "padding:12px 14px") do
          span(style: TYPE_BODY) { plain pay.provider_label }
        end
        td(style: "padding:12px 14px") do
          status_badge(pay.status)
        end
        td(style: "padding:12px 14px;white-space:nowrap") do
          span(style: TYPE_CAPTION) { plain pay.created_at.strftime("%d %b, %H:%M") }
        end
        td(style: "padding:12px 20px 12px 14px") do
          button(type: "button",
                 style: "display:flex;align-items:center;justify-content:center;" \
                        "width:28px;height:28px;border-radius:6px;border:none;" \
                        "background:transparent;cursor:pointer;color:#{SUBTLE_TEXT}") do
            span(style: "display:flex;width:14px;height:14px") do
              render UI::Icon.new(:dots_vertical, class: "w-full h-full")
            end
          end
        end
      end
    end

    def method_badge(method)
      cfg = case method
      when "mobile_money"
              { label: "Mobile Money", bg: "#fef9c3", text: "#854d0e" }
      when "card"
              { label: "Card",         bg: "#eff6ff", text: "#1d4ed8" }
      when "bank_transfer"
              { label: "Bank",         bg: "#f0fdf4", text: "#166534" }
      else
              { label: "—",            bg: "#f9fafb", text: "#9ca3af" }
      end
      span(style: "display:inline-flex;align-items:center;padding:2px 8px;border-radius:4px;" \
                  "background:#{cfg[:bg]};font-size:11.5px;font-weight:500;color:#{cfg[:text]}") do
        plain cfg[:label]
      end
    end

    def status_badge(status)
      cfg = case status
      when "paid", "succeeded", "success", "settled"
              { dot: GREEN,   bg: "rgba(22,163,74,0.08)",   text: "#15803d", label: "Paid" }
      when "initiated", "processing", "requires_action"
              { dot: AMBER,   bg: "rgba(217,119,6,0.08)",   text: "#b45309",
                label: status.tr("_", " ").split.map(&:capitalize).join(" ") }
      when "failed", "cancelled"
              { dot: RED,     bg: "rgba(220,38,38,0.08)",   text: "#b91c1c", label: status.capitalize }
      when "refunded", "partially_refunded"
              { dot: PURPLE,  bg: "rgba(109,40,217,0.08)",  text: "#5b21b6", label: "Refunded" }
      when "disputed"
              { dot: "#c2410c", bg: "rgba(194,65,12,0.08)", text: "#9a3412", label: "Disputed" }
      else
              { dot: SUBTLE_TEXT, bg: "rgba(156,163,175,0.08)", text: MUTED_TEXT,
                label: status.tr("_", " ").capitalize }
      end
      span(style: "display:inline-flex;align-items:center;gap:6px;padding:3px 10px;" \
                  "border-radius:20px;background:#{cfg[:bg]}") do
        span(style: "width:6px;height:6px;border-radius:50%;background:#{cfg[:dot]};flex-shrink:0")
        span(style: "font-size:12px;font-weight:500;color:#{cfg[:text]}") { plain cfg[:label] }
      end
    end

    def table_footer
      div(style: "display:flex;align-items:center;justify-content:space-between;" \
                 "padding:12px 20px;border-top:1px solid #{BORDER}") do
        p(style: "#{TYPE_CAPTION}") do
          plain "Showing last #{@recent_payments.size} payments · "
          a(href: payments_path,
            style: "color:#{BRAND};text-decoration:none;font-weight:500") { plain "View all →" }
        end
        div(style: "display:flex;align-items:center;gap:4px") do
          pg_btn(:chev_left)
          span(style: "font-size:12.5px;font-weight:500;color:#{BODY_TEXT};padding:0 8px") { plain "1" }
          pg_btn(:chev_right)
        end
      end
    end

    def pg_btn(icon_name)
      button(type: "button",
             style: "display:flex;align-items:center;justify-content:center;width:28px;height:28px;" \
                    "border-radius:6px;border:1px solid #{BORDER_MED};background:#fff;" \
                    "cursor:pointer;color:#{MUTED_TEXT}") do
        span(style: "display:flex;width:14px;height:14px") do
          render UI::Icon.new(icon_name, class: "w-full h-full")
        end
      end
    end

    def table_empty_state
      div(style: "padding:56px 20px;display:flex;flex-direction:column;align-items:center;" \
                 "justify-content:center;gap:10px;text-align:center") do
        div(style: "width:44px;height:44px;border-radius:12px;background:#f9fafb;" \
                   "display:flex;align-items:center;justify-content:center;margin-bottom:4px") do
          span(style: "color:#{FAINT_TEXT};display:flex;width:22px;height:22px") do
            render UI::Icon.new(:layers, class: "w-full h-full")
          end
        end
        p(style: TYPE_BODY_MD) { plain "No payments yet" }
        p(style: TYPE_CAPTION) { plain "Transactions will appear here once payments start flowing." }
      end
    end

    # ── ECharts JSON (uses real data from controller) ─────────────────────────

    def volume_chart_json
      {
        grid: { top: 10, right: 8, bottom: 28, left: 56 },
        xAxis: {
          type: "category",
          data: @chart_dates,
          boundaryGap: false,
          axisLine: { show: false },
          axisTick: { show: false },
          axisLabel: { color: "#9ca3af", fontSize: 10,
                       interval: (@chart_dates.size / 6).floor }
        },
        yAxis: {
          type: "value",
          splitLine: { lineStyle: { color: "#f3f4f6", type: "dashed" } },
          axisLabel: { color: "#9ca3af", fontSize: 10, formatter: "GHS {value}" }
        },
        series: [ {
          type: "line",
          smooth: true,
          data: @chart_values,
          showSymbol: false,
          lineStyle: { color: BRAND, width: 2 },
          itemStyle: { color: BRAND },
          areaStyle: {
            color: {
              type: "linear", x: 0, y: 0, x2: 0, y2: 1,
              colorStops: [
                { offset: 0, color: "rgba(61,71,245,0.13)" },
                { offset: 1, color: "rgba(61,71,245,0)" }
              ]
            }
          }
        } ],
        tooltip: {
          trigger: "axis",
          backgroundColor: "#fff",
          borderColor: "#e5e7eb",
          borderWidth: 1,
          textStyle: { color: "#374151", fontSize: 12 },
          padding: [ 8, 12 ],
          formatter: "GHS {c0}"
        }
      }.to_json
    end

    def donut_chart_json
      series_data = @provider_data.map do |p|
        { value: p[:amount_cents], name: p[:name],
          itemStyle: { color: p[:color] } }
      end

      {
        series: [ {
          type: "pie",
          radius: [ "55%", "82%" ],
          center: [ "50%", "50%" ],
          data: series_data,
          label: { show: false },
          emphasis: { label: { show: false } }
        } ],
        tooltip: {
          trigger: "item",
          backgroundColor: "#fff",
          borderColor: "#e5e7eb",
          borderWidth: 1,
          textStyle: { color: "#374151", fontSize: 12 },
          padding: [ 8, 12 ],
          formatter: "{b}: {d}%"
        }
      }.to_json
    end

    # ── Helpers ───────────────────────────────────────────────────────────────

    def format_volume
      "GHS #{fmt_decimal(@volume_cents / 100.0)}"
    end

    def rate_label
      @success_rate ? "#{@success_rate}%" : "—"
    end

    def rate_color
      return SUBTLE_TEXT unless @success_rate
      @success_rate >= 95 ? GREEN : @success_rate >= 80 ? AMBER : RED
    end

    def rate_tint
      return "rgba(156,163,175,0.08)" unless @success_rate
      @success_rate >= 95 ? "rgba(22,163,74,0.08)" :
        @success_rate >= 80 ? "rgba(217,119,6,0.08)" : "rgba(220,38,38,0.08)"
    end

    def volume_delta
      return nil if @prev_volume_cents.zero?
      ((@volume_cents - @prev_volume_cents).to_f / @prev_volume_cents * 100).round(1)
    end

    def tx_delta
      return nil if @prev_tx_count.zero?
      ((@tx_count - @prev_tx_count).to_f / @prev_tx_count * 100).round(1)
    end

    def fmt(n)
      n.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
    end

    def fmt_decimal(n)
      whole, frac = sprintf("%.2f", n).split(".")
      "#{fmt(whole.to_i)}.#{frac}"
    end
  end
end
