# frozen_string_literal: true

module Payments
  module SettlementBatches
    class ShowView < ApplicationComponent
      include UI::Theme

      def initialize(batch:)
        @b = batch
      end

      def view_template
        label = @b["id"]&.slice(0, 16) || "Batch"
        render Layout::Shell.new(
          active_nav:  :settlement_batches,
          title:       label,
          breadcrumbs: [
            { label: "Settlement Batches", url: settlement_batches_path },
            { label: label }
          ]
        ) do
          render UI::Grid.new(columns: :sidebar) do
            left_column
            right_column
          end
        end
      end

      private

      def left_column
        div(class: "flex flex-col gap-5") do
          hero_card
          details_card
        end
      end

      def right_column
        div(class: "flex flex-col gap-5") do
          amounts_card
          timeline_card
        end
      end

      def hero_card
        cur     = @b["currency"] || "GHS"
        gross   = @b["gross_amount"].to_i
        state   = @b["state"] || "pending"
        start_s = @b["period_start"] ? Time.parse(@b["period_start"]).strftime("%d %b %Y") : "—"
        end_s   = @b["period_end"]   ? Time.parse(@b["period_end"]).strftime("%d %b %Y") : "—"

        div(class: "bg-white border border-gray-100 rounded-2xl px-8 py-7") do
          div(class: "flex items-start justify-between mb-5") do
            div do
              p(class: "#{TYPE_CAPTION} mb-1") { plain "Gross settlement amount" }
              p(class: "#{TYPE_AMOUNT} text-gray-900") { plain format_money(gross, currency: cur) }
            end
            render UI::StatusBadge.new(status: state)
          end
          div(class: "grid grid-cols-3 gap-[1px] bg-gray-100 rounded-xl overflow-hidden") do
            meta_cell("Period start", start_s)
            meta_cell("Period end",   end_s)
            meta_cell("Payments",     (@b["payment_count"] || "—").to_s)
          end
        end
      end

      def details_card
        cur = @b["currency"] || "GHS"

        render UI::Card.new do |card|
          card.header("Batch details")
          card.body(padding: false) do
            render UI::DetailList.new do |list|
              list.row("Batch ID",  @b["id"] || "—", mono: true)
              list.row("Currency", cur)
              list.row("Mode",     @b["mode"] || "—")
              list.row("State")    { render UI::StatusBadge.new(status: @b["state"] || "pending") }

              ts = @b["inserted_at"]
              list.row("Created", ts ? Time.parse(ts).strftime("%d %b %Y at %H:%M UTC") : "—")

              settled = @b["settled_at"]
              list.row("Settled", settled ? Time.parse(settled).strftime("%d %b %Y at %H:%M UTC") : "—")
            end
          end
        end
      end

      def amounts_card
        cur   = @b["currency"] || "GHS"
        gross = @b["gross_amount"].to_i

        render UI::Card.new do |card|
          card.header("Amounts")
          card.body(padding: false) do
            render UI::DetailList.new do |list|
              list.row("Gross amount",  format_money(gross, currency: cur))
              list.row("Payment count", (@b["payment_count"] || "—").to_s)
            end
          end
        end
      end

      def timeline_card
        state       = @b["state"] || "pending"
        states      = %w[pending approved dispatched settled]
        current_idx = states.index(state) || 0

        render UI::Card.new do |card|
          card.header("State timeline")
          card.body do
            states.each_with_index do |s, i|
              done  = i <= current_idx
              color = done ? GREEN : BORDER
              div(class: "flex gap-3") do
                div(class: "flex flex-col items-center flex-shrink-0") do
                  div(class: "w-[10px] h-[10px] rounded-full flex-shrink-0 mt-[3px]", style: "background:#{color}")
                  div(class: "w-[1px] flex-1 bg-gray-100 mt-1") unless i == states.length - 1
                end
                div(class: i == states.length - 1 ? "" : "pb-[14px]") do
                  p(class: done ? TYPE_BODY_MD : TYPE_CAPTION) { plain s.capitalize }
                end
              end
            end
          end
        end
      end
    end
  end
end
