# frozen_string_literal: true

module Payments
  module Reserves
    class IndexView < ApplicationComponent
      include UI::Theme

      PER_PAGE = 50

      STATE_STYLES = {
        "pending"  => { badge: "badge-amber",  label: "Held"     },
        "released" => { badge: "badge-green",  label: "Released" },
        "drawn"    => { badge: "badge-red",    label: "Drawn"    }
      }.freeze

      def initialize(policy: nil, summary: {}, holds: [], page: 1, total: 0)
        @policy  = policy
        @summary = summary
        @holds   = holds
        @page    = page
        @total   = total
      end

      def view_template
        render Layout::Shell.new(
          active_nav:  :reserves,
          title:       "Rolling Reserve",
          breadcrumbs: [
            { label: "Payments", href: payments_path },
            { label: "Reserve"  }
          ]
        ) do
          render UI::PageHeader.new(
            title:    "Rolling Reserve",
            subtitle: "Funds withheld from settlements to cover chargebacks and disputes."
          )

          if @policy.nil? && @holds.empty?
            no_policy_state
          else
            div(class: "flex flex-col gap-5") do
              summary_stats
              policy_card  if @policy
              holds_table
            end
          end
        end
      end

      private

      # ── No policy state ───────────────────────────────────────────────────────

      def no_policy_state
        div(class: "bg-white border border-gray-100 rounded-2xl px-8 py-16 flex flex-col items-center text-center gap-4") do
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
        div(class: "bg-white border border-gray-100 rounded-2xl px-5 py-5 flex items-start gap-4") do
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

      # ── Policy card ───────────────────────────────────────────────────────────

      def policy_card
        p = @policy
        kind_label = p["kind"] == "rolling" ? "Rolling percentage" : p["kind"] == "fixed" ? "Fixed amount" : "Ad hoc"

        div(class: "bg-white border border-gray-100 rounded-2xl overflow-hidden") do
          div(class: "px-6 py-5 border-b border-gray-100 flex items-center justify-between") do
            div do
              p(class: TYPE_TITLE) { plain "Reserve policy" }
              p(class: "#{TYPE_CAPTION} mt-[3px]") { plain "The active rule governing how much is held from each settlement." }
            end
            if p["approved_by"]
              span(class: "badge-green text-[11.5px] font-semibold px-3 py-1 rounded-full") { plain "Approved" }
            else
              span(class: "badge-amber text-[11.5px] font-semibold px-3 py-1 rounded-full") { plain "Pending approval" }
            end
          end

          div(class: "grid grid-cols-3 divide-x divide-gray-100") do
            policy_stat("Type",        kind_label)
            if p["kind"] == "rolling"
              policy_stat("Rate",      "#{(p["percentage_bps"].to_f / 100).round(2)}%")
            else
              policy_stat("Amount",    format_amount(p["fixed_amount"], p["currency"] || "GHS"))
            end
            policy_stat("Hold period", "#{p["hold_days"] || 90} days")
          end
        end
      end

      def policy_stat(label, value)
        div(class: "px-6 py-5") do
          p(class: TYPE_MICRO) { plain label }
          p(class: "text-[15px] font-bold text-gray-900 mt-1") { plain value }
        end
      end

      # ── Holds table ───────────────────────────────────────────────────────────

      def holds_table
        div(class: "bg-white border border-gray-100 rounded-2xl overflow-hidden") do
          div(class: "px-6 py-5 border-b border-gray-100 flex items-center justify-between") do
            p(class: TYPE_TITLE) { plain "Reserve holds" }
            p(class: "#{TYPE_CAPTION} mt-[3px]") { plain "Individual amounts withheld, one per payment." }
          end

          if @holds.empty?
            div(class: "px-6 py-12 text-center") do
              p(class: TYPE_CAPTION) { plain "No reserve holds yet." }
            end
          else
            div(class: "overflow-x-auto") do
              table(class: "w-full text-left") do
                thead do
                  tr(class: "border-b border-gray-100") do
                    th(class: "px-6 py-3 #{TYPE_MICRO}") { plain "Payment" }
                    th(class: "px-6 py-3 #{TYPE_MICRO}") { plain "Amount" }
                    th(class: "px-6 py-3 #{TYPE_MICRO}") { plain "Status" }
                    th(class: "px-6 py-3 #{TYPE_MICRO}") { plain "Held on" }
                    th(class: "px-6 py-3 #{TYPE_MICRO}") { plain "Releases" }
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
                  from = (@page - 1) * PER_PAGE + 1
                  to   = [from + PER_PAGE - 1, @total].min
                  plain "#{from}–#{to} of #{@total}"
                end
                div(class: "flex gap-2") do
                  if @page > 1
                    render UI::Button.new(variant: :secondary, href: reserves_path(page: @page - 1)) { plain "← Previous" }
                  end
                  if @page * PER_PAGE < @total
                    render UI::Button.new(variant: :secondary, href: reserves_path(page: @page + 1)) { plain "Next →" }
                  end
                end
              end
            end
          end
        end
      end

      def hold_row(h)
        state  = h["state"] || "pending"
        style  = STATE_STYLES[state] || { badge: "badge-gray", label: state.capitalize }
        cur    = h["currency"] || "GHS"

        tr(class: "border-b border-gray-50 last:border-0 hover:bg-gray-50 transition-colors") do
          td(class: "px-6 py-3") do
            span(class: "font-mono text-[12px] text-gray-600") { plain short_id(h["payment_id"]) }
          end
          td(class: "px-6 py-3") do
            span(class: "text-[13px] font-semibold tabular-nums text-gray-900") { plain format_amount(h["amount"], cur) }
          end
          td(class: "px-6 py-3") do
            span(class: "#{style[:badge]} text-[11.5px] font-semibold px-[9px] py-[3px] rounded-full") { plain style[:label] }
          end
          td(class: "px-6 py-3") do
            span(class: "text-[12.5px] text-gray-500") { plain format_date(h["held_at"]) }
          end
          td(class: "px-6 py-3") do
            if state == "pending"
              span(class: "text-[12.5px] text-gray-500") { plain format_date(h["release_at"]) }
            elsif state == "released"
              span(class: "text-[12.5px] text-green-600 font-medium") { plain format_date(h["released_at"]) }
            else
              span(class: "text-[12.5px] text-red-500 font-medium") { plain "Drawn #{format_date(h["drawn_at"])}" }
            end
          end
        end
      end

      # ── Helpers ───────────────────────────────────────────────────────────────

      def format_amount(pence, currency)
        return "—" if pence.nil?
        value = pence.to_f / 100
        "#{currency} #{sprintf('%.2f', value)}"
      end

      def format_date(iso)
        return "—" if iso.nil?
        Time.parse(iso).strftime("%-d %b %Y") rescue "—"
      end

      def short_id(id)
        return "—" if id.nil?
        id.to_s.split("-").first || id.to_s.first(8)
      end
    end
  end
end
