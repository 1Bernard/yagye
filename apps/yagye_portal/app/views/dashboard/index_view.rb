# frozen_string_literal: true

module Dashboard
  class IndexView < ApplicationComponent
    include UI::Theme

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
      div(class: "grid grid-cols-3 gap-4 mb-5") do
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
      div(class: "bg-white border border-gray-100 rounded-2xl p-[22px]") do
        div(class: "flex items-start justify-between mb-[14px]") do
          div(class: "w-9 h-9 rounded-xl flex items-center justify-center flex-shrink-0",
              style: "background:#{tint}") do
            span(class: "flex w-[17px] h-[17px]", style: "color:#{color}") do
              render UI::Icon.new(icon, class: "w-full h-full")
            end
          end
          if delta
            positive    = delta >= 0
            delta_color = positive ? GREEN : RED
            delta_bg    = positive ? "rgba(22,163,74,0.08)" : "rgba(220,38,38,0.08)"
            span(class: "text-[11px] font-semibold px-[7px] py-[2px] rounded-full",
                 style: "color:#{delta_color};background:#{delta_bg}") do
              plain "#{positive ? '+' : ''}#{delta}%"
            end
          end
        end
        p(class: "#{TYPE_HEADING} mb-2") { plain label }
        p(class: "#{TYPE_STAT} text-gray-900") { plain value }
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
      div(class: "bg-white border border-gray-100 rounded-2xl overflow-hidden") do
        div(class: "flex items-center justify-between px-[22px] pt-[18px]") do
          div do
            p(class: TYPE_TITLE) { plain "Transaction Volume" }
            p(class: "#{TYPE_CAPTION} mt-[3px]") { plain "Daily paid volume · last 30 days" }
          end
          div(class: "flex items-center gap-1") do
            period_btn("7D", false)
            period_btn("30D", true)
            period_btn("3M", false)
          end
        end
        div(class: "px-[22px] pt-4 pb-5") do
          render UI::Chart::Line.new(
            labels: @chart_dates,
            data:   @chart_values,
            dataset_label: "Transaction Volume",
            area:   true,
            height: 220
          )
        end
      end
    end

    def provider_split_card
      div(class: "bg-white border border-gray-100 rounded-2xl px-[22px] pt-[18px] pb-[22px]") do
        p(class: "#{TYPE_TITLE} mb-[3px]") { plain "Provider Split" }
        p(class: "#{TYPE_CAPTION} mb-4") { plain "Volume by provider (MTD)" }

        render UI::Chart::Pie.new(
          labels: @provider_data.map { |p| p[:name] },
          data:   @provider_data.map { |p| p[:amount_cents] / 100.0 },
          colors: @provider_data.map { |p| p[:color] },
          height: 168
        )

        unless @provider_data.empty?
          div(class: "mt-4 flex flex-col gap-[10px]") do
            @provider_data.each { |p| provider_row(p) }
          end
        end
      end
    end

    def period_btn(label, active)
      if active
        button(type: "button",
               class: "text-[11.5px] font-semibold px-[10px] py-1 rounded-md cursor-pointer border-0 text-white bg-[#3D47F5]") do
          plain label
        end
      else
        button(type: "button",
               class: "text-[11.5px] font-medium px-[10px] py-1 rounded-md cursor-pointer border-0 bg-transparent text-gray-400") do
          plain label
        end
      end
    end

    def provider_row(prov)
      div(class: "flex items-center justify-between") do
        div(class: "flex items-center gap-2") do
          span(class: "w-2 h-2 rounded-full flex-shrink-0", style: "background:#{prov[:color]}")
          span(class: TYPE_CAPTION) { plain prov[:name] }
        end
        div(class: "flex items-center gap-2") do
          span(class: TYPE_CAPTION) { plain "#{prov[:pct]}%" }
          span(class: TYPE_MONO) { plain "GHS #{fmt_decimal(prov[:amount_cents] / 100.0)}" }
        end
      end
    end

    # ── Recent payments table ─────────────────────────────────────────────────

    def recent_table
      div(class: TABLE_CARD) do
        table_action_bar
        if @recent_payments.empty?
          table_empty_state
        else
          div(class: "overflow-x-auto") do
            table(class: "w-full border-collapse min-w-[780px]") do
              table_head
              tbody { @recent_payments.each { |pay| table_row(pay) } }
            end
          end
          table_footer
        end
      end
    end

    def table_action_bar
      div(class: "flex items-center justify-between px-5 py-[14px] border-b border-gray-100") do
        div(class: "flex items-center gap-[10px]") do
          p(class: TYPE_TITLE) { plain "Recent Payments" }
          unless @recent_payments.empty?
            span(class: "text-[11px] font-semibold px-2 py-[2px] bg-gray-50 rounded-full text-gray-500") do
              plain "Last #{@recent_payments.size}"
            end
          end
        end
        div(class: "flex items-center gap-2") do
          div(class: "flex items-center gap-2 px-3 py-[7px] border border-gray-200 rounded-[9px] min-w-[176px] cursor-text") do
            span(class: "text-gray-300 flex w-[13px] h-[13px] flex-shrink-0") do
              render UI::Icon.new(:search, class: "w-full h-full")
            end
            span(class: TYPE_CAPTION) { plain "Search payments…" }
          end
          render UI::Button.new(variant: :secondary, type: "button") do
            span(class: "flex w-[12px] h-[12px]") { render UI::Icon.new(:filter, class: "w-full h-full") }
            plain "Filter"
          end
          render UI::Button.new(variant: :secondary, type: "button") do
            span(class: "flex w-[12px] h-[12px]") { render UI::Icon.new(:download, class: "w-full h-full") }
            plain "Export"
          end
          render UI::Button.new(variant: :primary, href: payments_path) do
            plain "View all"
            span(class: "flex w-[13px] h-[13px]") { render UI::Icon.new(:arrow_right, class: "w-full h-full") }
          end
        end
      end
    end

    def table_head
      thead do
        tr(class: "border-b border-gray-100") do
          th(class: "px-3 py-[10px] pl-5 w-9") do
            input(type: "checkbox", class: CHECKBOX_INPUT)
          end
          th_col("Reference")
          th_col("Customer")
          th_col("Amount")
          th_col("Method")
          th_col("Provider")
          th_col("Status")
          th_col("Date")
          th(class: "px-5 py-[10px] pl-[14px] w-10")
        end
      end
    end

    def th_col(label)
      th(class: "px-[14px] py-[10px] text-left whitespace-nowrap cursor-pointer") do
        div(class: "inline-flex items-center gap-1") do
          span(class: TYPE_HEADING) { plain label }
          span(class: "text-gray-200 text-[10px]") { plain "↕" }
        end
      end
    end

    def table_row(pay)
      tr(class: TABLE_ROW) do
        td(class: "px-3 py-3 pl-5") do
          input(type: "checkbox", class: CHECKBOX_INPUT)
        end
        td(class: "px-[14px] py-3") { span(class: TYPE_MONO) { plain pay.reference.to_s } }
        td(class: "px-[14px] py-3") { span(class: TYPE_CAPTION) { plain pay.masked_msisdn } }
        td(class: "px-[14px] py-3") do
          span(class: "text-[13px] font-semibold text-gray-900 #{TYPE_NUM}") { plain pay.formatted_amount }
        end
        td(class: "px-[14px] py-3") { method_badge(pay.try(:payment_method).to_s) }
        td(class: "px-[14px] py-3") { span(class: TYPE_BODY) { plain pay.provider_label } }
        td(class: "px-[14px] py-3") { render UI::StatusBadge.new(pay.status) }
        td(class: "px-[14px] py-3 whitespace-nowrap") do
          span(class: TYPE_CAPTION) { plain pay.created_at.strftime("%d %b, %H:%M") }
        end
        td(class: "px-5 py-3 pl-[14px]") do
          render UI::Button.new(variant: :icon) do
            render UI::Icon.new(:dots_vertical, class: ICON_SM)
          end
        end
      end
    end

    def method_badge(method)
      cfg = case method
      when "mobile_money" then { label: "Mobile Money", bg: "#fef9c3", text: "#854d0e" }
      when "card"         then { label: "Card",         bg: "#eff6ff", text: "#1d4ed8" }
      when "bank_transfer" then { label: "Bank",        bg: "#f0fdf4", text: "#166534" }
      else                     { label: "—",            bg: "#f9fafb", text: "#9ca3af" }
      end
      span(class: "inline-flex items-center px-2 py-[2px] rounded text-[11.5px] font-medium",
           style: "background:#{cfg[:bg]};color:#{cfg[:text]}") do
        plain cfg[:label]
      end
    end

    def table_footer
      div(class: "flex items-center justify-between px-5 py-3 border-t border-gray-100") do
        p(class: TYPE_CAPTION) do
          plain "Showing last #{@recent_payments.size} payments · "
          a(href: payments_path, class: "text-[#3D47F5] no-underline font-medium") { plain "View all →" }
        end
        div(class: "flex items-center gap-1") do
          render UI::Button.new(variant: :icon) { render UI::Icon.new(:chev_left, class: ICON_SM) }
          span(class: "text-[12.5px] font-medium text-gray-700 px-2") { plain "1" }
          render UI::Button.new(variant: :icon) { render UI::Icon.new(:chev_right, class: ICON_SM) }
        end
      end
    end

    def table_empty_state
      div(class: "py-14 px-5 flex flex-col items-center justify-center gap-[10px] text-center") do
        div(class: "w-11 h-11 rounded-xl bg-gray-50 flex items-center justify-center mb-1") do
          span(class: "text-gray-300 flex w-[22px] h-[22px]") do
            render UI::Icon.new(:layers, class: "w-full h-full")
          end
        end
        p(class: TYPE_BODY_MD) { plain "No payments yet" }
        p(class: TYPE_CAPTION) { plain "Transactions will appear here once payments start flowing." }
      end
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
