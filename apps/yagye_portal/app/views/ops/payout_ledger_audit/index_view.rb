# frozen_string_literal: true

module Ops
  module PayoutLedgerAudit
    class IndexView < ApplicationComponent
      include UI::Theme

      def initialize(gaps:, mode:, count:)
        @gaps  = gaps
        @mode  = mode
        @count = count
      end

      def view_template
        render Layout::Shell.new(
          active_nav:  :reconciliation,
          title:       "Payout Ledger Audit",
          breadcrumbs: [ { label: "Reconciliation", href: reconciliation_path },
                         { label: "Payout Ledger Audit" } ]
        ) do
          render UI::PageHeader.new(
            title:    "Payout ledger audit",
            subtitle: "Paid payouts with no #{strong_text("payout_completed")} ledger entry. " \
                      "Each row indicates post_payout_completed did not run successfully."
          )

          stat_band
          mode_tabs
          @gaps.empty? ? empty_state : gaps_table
        end
      end

      private

      def strong_text(t)
        content_tag(:code, t, class: TYPE_MONO)
      end

      def stat_band
        render UI::Grid.new(columns: 3) do
          stat_cell("Gaps detected", @count.to_s,
                    icon: :alert_circle, color: @count.zero? ? GREEN : RED,
                    tint: @count.zero? ? TINT_GREEN : TINT_RED)
          stat_cell("Mode", @mode.capitalize,
                    icon: :layers, color: BRAND, tint: TINT_BRAND)
          stat_cell("Impact", @count.zero? ? "None" : "Ledger inconsistency",
                    icon: :trending_up, color: @count.zero? ? GREEN : AMBER,
                    tint: @count.zero? ? TINT_GREEN : TINT_AMBER)
        end
      end

      def mode_tabs
        div(class: "flex gap-2 mb-4") do
          %w[simulation live].each do |m|
            active = @mode == m
            a(href: ops_payout_ledger_audit_path(mode: m),
              class: "px-4 py-1.5 rounded-full text-[12.5px] font-medium border transition-colors " \
                     "#{active ? 'bg-[#3D47F5] text-white border-[#3D47F5]' : 'bg-white text-gray-600 border-gray-200 hover:border-gray-400'}") do
              plain m.capitalize
            end
          end
        end
      end

      def empty_state
        div(class: "py-16 text-center") do
          render UI::Icon.new(:check_circle, class: "w-10 h-10 mx-auto mb-3 text-green-400")
          p(class: "#{TYPE_BODY_MD} font-medium") { plain "No gaps found" }
          p(class: TYPE_CAPTION) { plain "All paid payouts have a corresponding ledger entry in #{@mode} mode." }
        end
      end

      def gaps_table
        render UI::Datatable.new(records: @gaps, empty_message: "No gaps.") do |t|
          t.column("Payout code") do |g|
            code(class: TYPE_MONO) { plain g["payout_code"] }
          end

          t.column("Amount", class: "text-right tabular-nums font-medium") do |g|
            plain format_money(g["amount"].to_i, currency: g["currency"] || "GHS")
          end

          t.column("Mode") do |g|
            render UI::StatusBadge.new(status: g["mode"])
          end

          t.column("Destination type") do |g|
            plain g["destination_type"].to_s.humanize
          end

          t.column("Provider ref") do |g|
            ref = g["provider_reference"]
            if ref.present?
              code(class: TYPE_MONO) { plain ref.first(20) }
            else
              span(class: "text-gray-400") { plain "—" }
            end
          end

          t.column("Completed at") do |g|
            plain g["completed_at"] ? fmt_datetime(Time.parse(g["completed_at"])) : "—"
          end
        end
      end
    end
  end
end
