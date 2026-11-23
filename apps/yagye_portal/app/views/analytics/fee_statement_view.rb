# frozen_string_literal: true

module Analytics
  class FeeStatementView < ApplicationComponent
    include UI::Theme

    PROVIDER_LABELS = Payment::PROVIDERS.merge(
      "stripe"      => "Stripe",
      "paystack"    => "Paystack",
      "flutterwave" => "Flutterwave"
    ).freeze

    # Fixed palette for fee distribution doughnut — distinct across CVD types.
    FEE_CHART_COLORS = %w[#3D47F5 #8b5cf6 #06b6d4 #d97706 #ec4899 #10b981 #f97316].freeze

    CURRENCY_PREFIXES = { "GHS" => "GH₵", "USD" => "$", "EUR" => "€", "GBP" => "£" }.freeze

    def initialize(rows:, total_fees:, from:, to:, currency:)
      @rows       = rows
      @total_fees = total_fees
      @from       = from
      @to         = to
      @currency   = currency
    end

    def view_template
      render Layout::Shell.new(
        active_nav:  :analytics_fee_statement,
        title:       "Fee Statement",
        breadcrumbs: [ { label: "Analytics" }, { label: "Fee Statement" } ]
      ) do
        render UI::PageHeader.new(
          title:    "Fee Statement",
          subtitle: "Platform fees charged by Yagye per provider for the selected period."
        )

        summary_band
        date_filter_bar
        chart_section
        fees_table
      end
    end

    private

    def summary_band
      tx_count = @rows.sum(&:tx_count)

      render UI::Grid.new(columns: 3) do
        stat_cell("Total fees", format_money(@total_fees, currency: @currency),
                  icon: :tag, color: BRAND, tint: TINT_BRAND)
        stat_cell("Transactions", tx_count.to_s,
                  icon: :layers, color: INK, tint: TINT_GRAY)
        stat_cell("Providers", @rows.size.to_s,
                  icon: :globe, color: GREEN, tint: TINT_GREEN)
      end
    end

    def date_filter_bar
      div(class: "flex items-center gap-3 mt-2 mb-1") do
        form(action: analytics_fee_statement_path, method: :get,
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
          a(href: analytics_provider_performance_path, class: LINK_MUTED) do
            plain "Provider Performance →"
          end
        end
      end
    end

    def fees_table
      if @rows.empty?
        empty_state
        return
      end

      div(class: "#{TABLE_CARD} mt-2") do
        div(class: "overflow-x-auto") do
          table(class: "w-full") do
            thead do
              tr(class: TABLE_HEADER) do
                th(class: TABLE_TH) { plain "Provider" }
                th(class: "#{TABLE_TH} text-right") { plain "Transactions" }
                th(class: "#{TABLE_TH} text-right") { plain "Gross volume" }
                th(class: "#{TABLE_TH} text-right") { plain "Net payout" }
                th(class: "#{TABLE_TH} text-right") { plain "Yagye fees" }
                th(class: "#{TABLE_TH} text-right") { plain "Fee %" }
              end
            end
            tbody do
              @rows.each { |r| fee_row(r) }
              total_row if @rows.size > 1
            end
          end
        end
      end
    end

    def fee_row(r)
      pct = r.gross_volume > 0 ? (r.total_fees.to_f / r.gross_volume * 100).round(2) : 0.0
      label = PROVIDER_LABELS.fetch(r.provider.to_s, r.provider.to_s.humanize)

      tr(class: TABLE_ROW) do
        td(class: TABLE_CELL) do
          div(class: "flex items-center gap-2.5") do
            div(class: "w-7 h-7 rounded-lg bg-gray-100 border border-gray-200 flex items-center justify-center flex-shrink-0") do
              span(class: "text-[9px] font-extrabold text-gray-500 uppercase") { plain r.provider.to_s.first(3) }
            end
            p(class: TYPE_BODY_MD) { plain label }
          end
        end
        td(class: "#{TABLE_CELL} text-right tabular-nums") { plain r.tx_count.to_s }
        td(class: "#{TABLE_CELL} text-right tabular-nums") { plain format_money(r.gross_volume, currency: r.currency) }
        td(class: "#{TABLE_CELL} text-right tabular-nums") { plain format_money(r.net_volume, currency: r.currency) }
        td(class: "#{TABLE_CELL} text-right font-semibold text-gray-900 tabular-nums") do
          plain format_money(r.total_fees, currency: r.currency)
        end
        td(class: "#{TABLE_CELL} text-right tabular-nums") do
          span(class: "#{BADGE_XS} #{pct > 2.0 ? STATUS_WARNING : STATUS_NEUTRAL}") do
            plain "#{pct}%"
          end
        end
      end
    end

    def total_row
      total_gross = @rows.sum(&:gross_volume)
      total_net   = @rows.sum(&:net_volume)
      total_tx    = @rows.sum(&:tx_count)
      total_pct   = total_gross > 0 ? (@total_fees.to_f / total_gross * 100).round(2) : 0.0
      currency    = @rows.first&.currency || @currency

      tr(class: "bg-gray-50 border-t-2 border-gray-200") do
        td(class: "#{TABLE_CELL} font-semibold text-gray-900") { plain "Total" }
        td(class: "#{TABLE_CELL} text-right font-semibold text-gray-900 tabular-nums") { plain total_tx.to_s }
        td(class: "#{TABLE_CELL} text-right font-semibold text-gray-900 tabular-nums") { plain format_money(total_gross, currency: currency) }
        td(class: "#{TABLE_CELL} text-right font-semibold text-gray-900 tabular-nums") { plain format_money(total_net, currency: currency) }
        td(class: "#{TABLE_CELL} text-right font-bold text-gray-900 tabular-nums") { plain format_money(@total_fees, currency: currency) }
        td(class: "#{TABLE_CELL} text-right tabular-nums") do
          span(class: "#{BADGE_XS} #{STATUS_NEUTRAL}") { plain "#{total_pct}% avg" }
        end
      end
    end

    def chart_section
      return if @rows.empty?

      labels    = @rows.map { |r| PROVIDER_LABELS.fetch(r.provider.to_s, r.provider.to_s.humanize) }
      fee_data  = @rows.map { |r| (r.total_fees / 100.0).round(2) }
      formatted = @rows.map { |r| format_money(r.total_fees, currency: r.currency) }
      colors    = FEE_CHART_COLORS.first(@rows.size)
      prefix    = CURRENCY_PREFIXES.fetch(@currency, "")
      h         = bar_height(@rows.size)

      div(class: "grid grid-cols-5 gap-4 mt-4") do
        div(class: "col-span-3") do
          chart_card("Fees by channel") do
            render UI::Chart::Bar.new(
              labels:                  labels,
              data:                    fee_data,
              dataset_label:           "Fees",
              horizontal:              true,
              item_colors:             colors,
              value_prefix:            prefix,
              formatted_data_override: formatted,
              height:                  h
            )
          end
        end

        div(class: "col-span-2") do
          chart_card("Fee distribution") do
            render UI::Chart::Pie.new(
              labels:          labels,
              data:            fee_data,
              colors:          colors,
              ring:            true,
              center_label:    format_money(@total_fees, currency: @currency),
              center_sublabel: "total fees",
              height:          h
            )
          end
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
          span(class: "flex w-6 h-6 text-gray-400") { render UI::Icon.new(:tag, class: "w-full h-full") }
        end
        div(class: "text-center") do
          p(class: TYPE_TITLE) { plain "No fee data for this period" }
          p(class: "#{TYPE_CAPTION} mt-1 max-w-[320px]") do
            plain "No paid transactions with fees found for the selected date range."
          end
        end
      end
    end
  end
end
