# frozen_string_literal: true

module Analytics
  class ProviderPerformanceView < ApplicationComponent
    include UI::Theme

    PROVIDER_LABELS = Payment::PROVIDERS.merge(
      "stripe"      => "Stripe",
      "paystack"    => "Paystack",
      "flutterwave" => "Flutterwave"
    ).freeze

    def initialize(rows:, from:, to:, currency:)
      @rows     = rows
      @from     = from
      @to       = to
      @currency = currency
    end

    def view_template
      render Layout::Shell.new(
        active_nav:  :analytics_provider_performance,
        title:       "Channel Performance",
        breadcrumbs: [ { label: "Analytics" }, { label: "Channel Performance" } ]
      ) do
        render UI::PageHeader.new(
          title:    "Channel Performance",
          subtitle: "Success rates, volume, and avg latency across all payment channels."
        )

        summary_band
        date_filter_bar
        chart_section
        performance_table
      end
    end

    private

    def summary_band
      total_volume   = @rows.sum(&:gross_volume)
      total_tx       = @rows.sum(&:terminal_count)
      overall_rate   = if total_tx > 0
        total_succeeded = @rows.sum(&:succeeded_count)
        (total_succeeded.to_f / total_tx * 100).round(1)
      else
        0.0
      end

      rate_color = overall_rate >= 90 ? GREEN : (overall_rate >= 70 ? AMBER : RED)
      rate_tint  = overall_rate >= 90 ? TINT_GREEN : (overall_rate >= 70 ? TINT_AMBER : TINT_RED)

      render UI::Grid.new(columns: 3) do
        stat_cell("Total volume", format_money(total_volume, currency: @currency),
                  icon: :trending_up, color: BRAND, tint: TINT_BRAND)
        stat_cell("Overall success rate", "#{overall_rate}%",
                  icon: :check_circle, color: rate_color, tint: rate_tint)
        stat_cell("Channels tracked", @rows.size.to_s,
                  icon: :layers, color: INK, tint: TINT_GRAY)
      end
    end

    def date_filter_bar
      div(class: "flex items-center gap-3 mt-2 mb-1 flex-wrap") do
        form(action: analytics_provider_performance_path, method: :get,
             class: "flex items-center gap-3 flex-wrap") do
          input(type: "hidden", name: "currency", value: @currency)

          div(class: "flex items-center gap-2") do
            label(class: TYPE_MICRO, for: "from") { plain "FROM" }
            input(type: "date", id: "from", name: "from",
                  value: @from.to_date.iso8601,
                  class: "text-[12.5px] border border-gray-200 rounded-lg px-2.5 py-1.5 focus:outline-none focus:ring-2 focus:ring-blue-500")
          end

          div(class: "flex items-center gap-2") do
            label(class: TYPE_MICRO, for: "to") { plain "TO" }
            input(type: "date", id: "to", name: "to",
                  value: @to.to_date.iso8601,
                  class: "text-[12.5px] border border-gray-200 rounded-lg px-2.5 py-1.5 focus:outline-none focus:ring-2 focus:ring-blue-500")
          end

          button(type: "submit", class: "#{BADGE} #{STATUS_NEUTRAL} cursor-pointer hover:bg-gray-200 transition-colors") do
            plain "Apply"
          end
        end

        div(class: "ml-auto flex items-center gap-2") do
          a(href: analytics_fee_statement_path, class: LINK_MUTED) do
            plain "Fee Statement →"
          end
        end
      end
    end

    def performance_table
      if @rows.empty?
        empty_state
        return
      end

      div(class: "#{TABLE_CARD} mt-2") do
        div(class: "overflow-x-auto") do
          table(class: "w-full") do
            thead do
              tr(class: TABLE_HEADER) do
                th(class: TABLE_TH) { plain "Channel" }
                th(class: "#{TABLE_TH} text-right") { plain "Success rate" }
                th(class: "#{TABLE_TH} text-right") { plain "Succeeded" }
                th(class: "#{TABLE_TH} text-right") { plain "Failed" }
                th(class: "#{TABLE_TH} text-right") { plain "Volume" }
                th(class: "#{TABLE_TH} text-right") { plain "Avg latency" }
                th(class: "#{TABLE_TH} text-right") { plain "Fees paid" }
              end
            end
            tbody do
              @rows.each { |r| performance_row(r) }
            end
          end
        end
      end
    end

    def performance_row(r)
      rate       = r.success_rate
      rate_badge = rate >= 90 ? STATUS_SUCCESS : (rate >= 70 ? STATUS_WARNING : STATUS_FAILED)
      label      = PROVIDER_LABELS.fetch(r.provider.to_s, r.provider.to_s.humanize)
      latency    = format_latency(r.avg_latency_secs)

      tr(class: TABLE_ROW) do
        td(class: TABLE_CELL) do
          div(class: "flex items-center gap-2.5") do
            div(class: "w-7 h-7 rounded-lg bg-gray-100 border border-gray-200 flex items-center justify-center flex-shrink-0") do
              span(class: "text-[9px] font-extrabold text-gray-500 uppercase") { plain r.provider.to_s.first(3) }
            end
            p(class: TYPE_BODY_MD) { plain label }
          end
        end

        td(class: "#{TABLE_CELL} text-right") do
          success_bar(rate, rate_badge)
        end

        td(class: "#{TABLE_CELL} text-right tabular-nums text-green-700 font-medium") do
          plain r.succeeded_count.to_s
        end

        td(class: "#{TABLE_CELL} text-right tabular-nums text-red-500 font-medium") do
          plain r.failed_count.to_s
        end

        td(class: "#{TABLE_CELL} text-right tabular-nums") do
          plain format_money(r.gross_volume, currency: r.currency)
        end

        td(class: "#{TABLE_CELL} text-right tabular-nums") do
          plain latency
        end

        td(class: "#{TABLE_CELL} text-right tabular-nums") do
          plain r.total_fees > 0 ? format_money(r.total_fees, currency: r.currency) : "—"
        end
      end
    end

    def success_bar(rate, badge_class)
      div(class: "flex items-center gap-2 justify-end") do
        div(class: "w-20 bg-gray-100 rounded-full", style: "height:4px") do
          div(class: "rounded-full h-full",
              style: "width:#{[ rate, 100 ].min}%;background:#{rate_color(rate)}")
        end
        span(class: "#{BADGE_XS} #{badge_class} tabular-nums") { plain "#{rate}%" }
      end
    end

    def rate_color(rate)
      return GREEN if rate >= 90
      return AMBER if rate >= 70
      RED
    end

    def format_latency(secs)
      return "—" if secs.nil? || secs <= 0
      return "#{secs}s" if secs < 60
      "#{(secs / 60.0).round(1)}m"
    end

    def chart_section
      return if @rows.empty?

      labels    = @rows.map { |r| PROVIDER_LABELS.fetch(r.provider.to_s, r.provider.to_s.humanize) }
      rates     = @rows.map(&:success_rate)
      colors    = @rows.map { |r| rate_color(r.success_rate) }
      formatted = @rows.map { |r| "#{r.success_rate}% (#{r.succeeded_count}/#{r.terminal_count})" }
      h         = bar_height(@rows.size)

      div(class: "mt-4") do
        chart_card("Success rate by channel") do
          render UI::Chart::Bar.new(
            labels:                  labels,
            data:                    rates,
            dataset_label:           "Success rate",
            horizontal:              true,
            item_colors:             colors,
            value_suffix:            "%",
            formatted_data_override: formatted,
            height:                  h
          )
        end
      end
    end

    def chart_card(title, &block)
      div(class: "#{SURFACE_CARD} p-4 flex flex-col gap-3") do
        p(class: TYPE_LABEL) { plain title }
        block.call
      end
    end

    def bar_height(n)
      [n * 44 + 24, 200].max
    end

    def empty_state
      div(class: "#{SURFACE_CARD} flex flex-col items-center justify-center py-20 gap-4 mt-2") do
        div(class: "w-14 h-14 rounded-2xl bg-gray-100 flex items-center justify-center") do
          span(class: "flex w-6 h-6 text-gray-400") { render UI::Icon.new(:layers, class: "w-full h-full") }
        end
        div(class: "text-center") do
          p(class: TYPE_TITLE) { plain "No performance data for this period" }
          p(class: "#{TYPE_CAPTION} mt-1 max-w-[360px]") do
            plain "No terminal payments found for the selected date range and currency."
          end
        end
      end
    end
  end
end
