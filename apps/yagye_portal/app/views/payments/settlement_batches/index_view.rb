# frozen_string_literal: true

module Payments
  module SettlementBatches
    class IndexView < ApplicationComponent
      include UI::Theme

      def initialize(batches:, summary: {})
        @batches = batches
        @summary = summary
      end

      def view_template
        render Layout::Shell.new(
          active_nav: :settlement_batches,
          title:      "Settlement Batches",
          subtitle:   "Daily settlement runs grouped by period"
        ) do
          render UI::PageHeader.new(
            title:    "Settlement Batches",
            subtitle: "Each batch covers payments settled in a given period."
          )

          settlement_summary_strip if @summary.any?

          batches_table
        end
      end

      private

      # ── Settlement KPI strip ─────────────────────────────────────────────────

      def settlement_summary_strip
        payables    = Array(@summary["payable_balances"])
        destination = @summary["destination"] || {}
        batches_by_state = pipeline_counts

        div(class: "grid grid-cols-1 sm:grid-cols-3 gap-4 mb-6") do
          pending_payout_card(payables)
          destination_card(destination)
          pipeline_card(batches_by_state)
        end
      end

      def pending_payout_card(payables)
        if payables.empty?
          summary_card(icon: :wallet, color: AMBER, tint: TINT_AMBER,
                       label: "Pending Payout", value: "—",
                       sub: "No unsettled balance")
        else
          primary = payables.first
          amt     = format_money(primary["balance"].to_i, currency: primary["currency"])
          others  = payables.size > 1 ? "+ #{payables.size - 1} more" : nil
          summary_card(icon: :wallet, color: AMBER, tint: TINT_AMBER,
                       label: "Pending Payout", value: amt,
                       sub: "#{primary['mode']} · #{others || 'awaiting disbursement'}")
        end
      end

      def destination_card(destination)
        case destination["type"]
        when "mobile_wallet"
          msisdn = destination["msisdn"].to_s
          masked = msisdn.length > 6 ? "#{msisdn[0..2]} *** #{msisdn[-4..]}" : msisdn
          summary_card(icon: :smartphone, color: GREEN, tint: TINT_GREEN,
                       label: "Disbursed To", value: "Mobile Wallet",
                       sub: masked)
        when "bank_account"
          acct   = destination["account_number"].to_s
          masked = acct.length > 4 ? "••••#{acct[-4..]}" : acct
          summary_card(icon: :bank, color: BRAND, tint: TINT_BRAND,
                       label: "Disbursed To", value: destination["account_name"] || "Bank Account",
                       sub: "#{destination['bank_code']} · #{masked}")
        else
          summary_card(icon: :alert_triangle, color: RED, tint: TINT_RED,
                       label: "Disbursed To", value: "Not configured",
                       sub: "Set up settlement controls")
        end
      end

      def pipeline_card(counts)
        pending  = counts["pending"].to_i + counts["processing"].to_i
        awaiting = counts["awaiting_approval"].to_i
        failed   = counts["failed"].to_i + counts["dispatch_rejected"].to_i

        color =
          if failed > 0 then RED
          elsif awaiting > 0 then AMBER
          else GREEN
          end
        tint =
          if failed > 0 then TINT_RED
          elsif awaiting > 0 then TINT_AMBER
          else TINT_GREEN
          end

        lines = []
        lines << "#{pending} pending"       if pending > 0
        lines << "#{awaiting} awaiting approval" if awaiting > 0
        lines << "#{failed} failed"         if failed > 0
        lines << "All clear"                if lines.empty?

        summary_card(icon: :layers, color: color, tint: tint,
                     label: "Settlement Pipeline", value: "#{counts.values.sum} total",
                     sub: lines.first)
      end

      def summary_card(icon:, color:, tint:, label:, value:, sub: nil)
        div(class: "bg-white border border-gray-100 rounded-2xl p-5") do
          div(class: "flex items-center gap-3 mb-3") do
            div(class: "w-8 h-8 rounded-xl flex items-center justify-center flex-shrink-0",
                style: "background:#{tint}") do
              span(class: "flex w-4 h-4", style: "color:#{color}") do
                render UI::Icon.new(icon, class: "w-full h-full")
              end
            end
            span(class: "text-xs font-medium text-gray-500 uppercase tracking-wide") { plain label }
          end
          p(class: "text-xl font-bold text-gray-900 leading-tight") { plain value }
          p(class: "text-xs text-gray-400 mt-0.5") { plain sub } if sub
        end
      end

      def pipeline_counts
        recent = Array(@batches)
        counts = Hash.new(0)
        recent.each { |b| counts[b["state"]] += 1 }
        counts
      end

      # ── Batches table ────────────────────────────────────────────────────────

      def batches_table
        render UI::Datatable.new(
          records:       @batches,
          pagy:          nil,
          empty_message: "No settlement batches yet."
        ) do |t|
          t.column("#", class: "text-gray-400 tabular-nums text-right w-8") { |_, i| plain((i + 1).to_s) }

          t.column("Period") do |b|
            ps = b["period_start"] ? Time.parse(b["period_start"]).strftime("%d %b") : "—"
            pe = b["period_end"]   ? Time.parse(b["period_end"]).strftime("%d %b %Y") : "—"
            plain "#{ps} – #{pe}"
          end

          t.column("Payments", class: "tabular-nums text-right") do |b|
            plain((b["payment_count"] || "—").to_s)
          end

          t.column("Gross", class: "tabular-nums text-right font-semibold") do |b|
            amt = b["gross_amount"].to_i
            plain(format_money(amt, currency: b["currency"] || "GHS"))
          end

          t.column("Status") do |b|
            render UI::StatusBadge.new(status: b["state"] || "pending")
          end

          t.column("Settled") do |b|
            ts = b["settled_at"]
            plain(ts ? Time.parse(ts).strftime("%d %b %Y") : "—")
          end

          t.actions do |b|
            a(href: settlement_batch_path(b["id"]), class: DROPDOWN_ITEM) do
              render UI::Icon.new(:eye, class: ICON_SM)
              plain "View"
            end
          end
        end
      end
    end
  end
end
