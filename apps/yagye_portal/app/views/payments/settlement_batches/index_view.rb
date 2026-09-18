# frozen_string_literal: true

module Payments
  module SettlementBatches
    class IndexView < ApplicationComponent
      include UI::Theme

      def initialize(batches:)
        @batches = batches
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

          batches_table
        end
      end

      private

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

          t.column("State") do |b|
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
