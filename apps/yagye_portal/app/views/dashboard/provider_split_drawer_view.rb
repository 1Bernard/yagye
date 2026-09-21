# frozen_string_literal: true

module Dashboard
  class ProviderSplitDrawerView < ApplicationComponent
    include UI::Theme

    def initialize(provider_code:, provider_name:, color:, rows:, total:)
      @provider_code = provider_code
      @provider_name = provider_name
      @color         = color
      @rows          = rows
      @total         = total
    end

    def view_template
      turbo_frame_tag "drawer-frame" do
        div(class: DRAWER_HEAD) do
          div do
            p(class: TYPE_TITLE) { plain @provider_name }
            p(class: "#{TYPE_CAPTION} mt-[3px]") { plain "Merchant breakdown · MTD" }
          end
          button(type: "button", class: XBTN,
                 data: { action: "click->drawer#close" }) { plain "✕" }
        end

        div(class: "flex-1 overflow-y-auto") do
          if @rows.empty?
            div(class: "py-16 px-6 text-center") do
              p(class: TYPE_BODY_MD) { plain "No paid transactions this month" }
              p(class: "#{TYPE_CAPTION} mt-1") { plain "for #{@provider_name}" }
            end
          else
            summary_stats_section
            merchant_list_section
          end
        end
      end
    end

    private

    # ── Summary stats ─────────────────────────────────────────────────────────

    def summary_stats_section
      total_tx  = @rows.sum { |r| r.tx_count.to_i }
      total_avg = total_tx > 0 ? (@total / total_tx.to_f).round(0).to_i : 0

      div(class: "px-5 py-5 border-b border-gray-100") do
        div(class: "grid grid-cols-3 gap-[1px] bg-gray-100 rounded-xl overflow-hidden") do
          headline_stat("Volume",       format_money(@total),   :trending_up)
          headline_stat("Transactions", total_tx.to_s,          :layers)
          headline_stat("Avg ticket",   format_money(total_avg), :tag)
        end
      end
    end

    def headline_stat(label, value, icon)
      div(class: "bg-white px-3.5 py-3 flex items-center gap-2.5") do
        div(class: "w-7 h-7 rounded-[8px] bg-gray-100 border border-gray-200 " \
                   "flex items-center justify-center flex-shrink-0") do
          span(class: "flex w-3 h-3 text-gray-400") do
            render UI::Icon.new(icon, class: "w-full h-full")
          end
        end
        div do
          p(class: "text-[9.5px] font-semibold text-gray-400 uppercase tracking-widest mb-[2px]") { plain label }
          p(class: "text-[12.5px] font-bold text-gray-900 tabular-nums leading-none") { plain value }
        end
      end
    end

    # ── Merchant list ─────────────────────────────────────────────────────────

    def merchant_list_section
      div(class: "px-5 pt-5 pb-2") do
        p(class: TYPE_MICRO) { plain "By merchant" }
      end
      div(class: "divide-y divide-gray-50") do
        @rows.each_with_index { |row, i| merchant_row(row, i + 1) }
      end
    end

    def merchant_row(row, rank)
      volume  = row.total_volume.to_i
      tx      = row.tx_count.to_i
      pct     = @total > 0 ? (volume.to_f / @total * 100).round(1) : 0.0
      avg     = tx > 0 ? (volume / tx.to_f).round(0).to_i : 0
      name    = row.merchant_name.to_s
      code    = row.merchant_code.to_s
      uuid_re = /\A[0-9a-f]{8}-[0-9a-f]{4}-/i
      display = name.presence || (uuid_re.match?(code) ? "#{code.first(8)}…" : code)

      div(class: "px-5 py-[13px]") do
        div(class: "flex items-center gap-3 mb-[9px]") do
          div(class: "w-[30px] h-[30px] rounded-[9px] flex items-center justify-center flex-shrink-0",
              style: "background:#{@color}18") do
            span(class: "text-[11px] font-extrabold tabular-nums",
                 style: "color:#{@color}") { plain rank.to_s }
          end

          div(class: "flex-1 min-w-0") do
            p(class: "text-[12.5px] font-semibold text-gray-800 leading-tight truncate") { plain display }
            if display != code && code.present?
              p(class: "text-[10.5px] text-gray-400 font-mono leading-tight mt-px") { plain code }
            end
          end

          div(class: "flex-shrink-0 text-right") do
            p(class: "text-[13px] font-bold text-gray-900 tabular-nums leading-tight") do
              plain format_money(volume)
            end
            p(class: "text-[10.5px] text-gray-400 tabular-nums mt-px leading-tight") do
              plain "#{tx} txn#{tx == 1 ? '' : 's'} · #{pct}%"
            end
          end
        end

        div(class: "ml-[42px] bg-gray-100 rounded-full", style: "height:4px") do
          div(class: "rounded-full h-full", style: "width:#{pct}%;background:#{@color}")
        end
        p(class: "text-[10.5px] text-gray-400 ml-[42px] mt-[5px] tabular-nums") do
          plain "avg. #{format_money(avg)} / transaction"
        end
      end
    end
  end
end
