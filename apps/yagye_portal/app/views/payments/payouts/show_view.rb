# frozen_string_literal: true

module Payments
  module Payouts
    class ShowView < ApplicationComponent
      include UI::Theme

      def initialize(payout:)
        @payout = payout
      end

      def view_template
        render Layout::Shell.new(
          active_nav: :payouts,
          title:      @payout.payout_code.first(16),
          breadcrumbs: [
            { label: "Payouts", url: payouts_path },
            { label: @payout.payout_code.first(16) }
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
          state_card
          failure_card if @payout.failure_code.present?
        end
      end

      def hero_card
        div(class: "bg-white border border-gray-100 rounded-2xl px-8 py-7") do
          div(class: "flex items-start justify-between mb-5") do
            div do
              p(class: "#{TYPE_CAPTION} mb-1") { plain "Payout amount" }
              p(class: "#{TYPE_AMOUNT} text-gray-900") { plain @payout.formatted_amount }
            end
            render UI::StatusBadge.new(status: @payout.state)
          end
          div(class: "grid grid-cols-3 gap-[1px] bg-gray-100 rounded-xl overflow-hidden") do
            meta_cell("Destination",  @payout.destination_type&.humanize || "—")
            meta_cell("Scheduled",    @payout.scheduled_for&.strftime("%d %b %Y") || "—")
            meta_cell("Mode",         @payout.mode&.capitalize || "—")
          end
        end
      end

      def details_card
        div(class: "bg-white border border-gray-100 rounded-2xl overflow-hidden") do
          div(class: "px-6 py-5 border-b border-gray-100") do
            p(class: TYPE_TITLE) { plain "Payout details" }
          end
          render UI::DetailList.new do |list|
            list.row("Payout code",   @payout.payout_code, mono: true)
            list.row("Merchant code", @payout.merchant_code || "—", mono: true)
            list.row("Amount",        @payout.formatted_amount)
            list.row("Currency",      @payout.currency)
            list.row("State")         { render UI::StatusBadge.new(status: @payout.state) }
            list.row("Destination",   @payout.destination_type&.humanize || "—")
            list.row("Fingerprint",   @payout.destination_fingerprint || "—", mono: true)
            list.row("Scheduled for", @payout.scheduled_for&.strftime("%d %b %Y, %H:%M") || "—")
            list.row("Last updated",  @payout.last_applied_at&.strftime("%d %b %Y at %H:%M UTC") || "—")
            list.row("Version",       @payout.aggregate_version.to_s, mono: true)
          end
        end
      end

      def state_card
        div(class: "bg-white border border-gray-100 rounded-2xl overflow-hidden") do
          div(class: "px-6 py-5 border-b border-gray-100") do
            p(class: TYPE_TITLE) { plain "State timeline" }
          end
          div(class: "px-6 py-5") do
            state_steps.each_with_index do |(label, done), i|
              state_step(label, done, last: i == state_steps.length - 1)
            end
          end
        end
      end

      def state_step(label, done, last: false)
        color = done ? "#16a34a" : BORDER
        div(class: "flex gap-3") do
          div(class: "flex flex-col items-center flex-shrink-0") do
            div(class: "w-[10px] h-[10px] rounded-full flex-shrink-0 mt-[3px]", style: "background:#{color}")
            div(class: "w-[1px] flex-1 bg-gray-100 mt-1") unless last
          end
          div(class: last ? "" : "pb-[14px]") do
            p(class: (done ? TYPE_BODY_MD : TYPE_CAPTION)) { plain label }
          end
        end
      end

      def state_steps
        current = @payout.state
        order   = %w[scheduled validating reserving submitted paid]
        order.map { |s| [ s.humanize, reached?(current, s, order) ] }
      end

      def reached?(current, step, order)
        order.index(current).to_i >= order.index(step).to_i
      end

      def failure_card
        div(class: "bg-white border border-red-300 rounded-2xl overflow-hidden") do
          div(class: "px-5 py-[18px] border-b border-red-200") do
            p(class: "text-[13px] font-semibold text-red-600") { plain "Failure details" }
          end
          div(class: "px-5 py-4") do
            p(class: TYPE_CAPTION) { plain "Failure code" }
            p(class: "#{TYPE_MONO} mt-1 text-red-600") { plain @payout.failure_code }
          end
        end
      end

      def meta_cell(label, value)
        div(class: "bg-white px-[18px] py-[14px]") do
          p(class: "#{TYPE_MICRO} mb-[3px]") { plain label }
          p(class: TYPE_BODY_MD) { plain value }
        end
      end
    end
  end
end
