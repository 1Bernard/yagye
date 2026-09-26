# frozen_string_literal: true

module Payments
  module Payouts
    class ShowView < ApplicationComponent
      include UI::Theme

      FAILURE_DIAGNOSES = {
        "destination_inactive"        => {
          title:    "Destination wallet inactive",
          message:  "The MoMo wallet or bank account set as your payout destination is no longer active.",
          guidance: "Contact your network operator to reactivate the wallet, or add a new verified destination and request a fresh payout."
        },
        "destination_unverified"      => {
          title:    "Destination not verified",
          message:  "The payout destination hasn't completed the verification process.",
          guidance: "Complete name-enquiry verification for your payout destination before retrying."
        },
        "insufficient_payable_balance" => {
          title:    "Insufficient settled balance",
          message:  "There wasn't enough settled balance to cover this payout at the time of processing.",
          guidance: "Your pending settlements may not have cleared yet. Once new settlements are reconciled, the next scheduled payout will include these funds."
        }
      }.freeze

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
        render UI::Card.new do |c|
          c.header("Payout details")
          c.body(padding: false) do
            render UI::DetailList.new do |list|
              list.row("Payout code",   @payout.payout_code, mono: true)
              list.row("Merchant code", @payout.merchant_code || "—", mono: true)
              list.row("Amount",        @payout.formatted_amount)
              list.row("Currency",      @payout.currency)
              list.row("Status")         { render UI::StatusBadge.new(status: @payout.state) }
              list.row("Destination",   @payout.destination_type&.humanize || "—")
              list.row("Fingerprint",   @payout.destination_fingerprint || "—", mono: true)
              list.row("Scheduled for", @payout.scheduled_for&.strftime("%d %b %Y, %H:%M") || "—")
              list.row("Last updated",  @payout.last_applied_at&.strftime("%d %b %Y at %H:%M UTC") || "—")
              list.row("Version",       @payout.aggregate_version.to_s, mono: true)
            end
          end
        end
      end

      def state_card
        render UI::Card.new do |c|
          c.header("State timeline")
          c.body do
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
        raw_code = @payout.failure_code.to_s
        base_key = raw_code.split(":").first
        diag     = FAILURE_DIAGNOSES[base_key]
        is_internal = raw_code.start_with?("ledger_commit_failed")

        div(class: "bg-white border border-red-200 rounded-2xl overflow-hidden") do
          div(class: "flex items-center gap-2 px-5 py-[14px] bg-red-50 border-b border-red-100") do
            span(class: "flex w-4 h-4 text-red-500 flex-shrink-0") do
              render UI::Icon.new(:alert_circle, class: "w-full h-full")
            end
            p(class: "text-[13px] font-semibold text-red-700") do
              plain diag ? diag[:title] : (is_internal ? "Internal processing error" : "Payout failed")
            end
          end

          div(class: "px-5 py-4 flex flex-col gap-3") do
            if diag
              p(class: "text-[13px] text-gray-700 leading-relaxed") { plain diag[:message] }
              div(class: "bg-amber-50 border border-amber-100 rounded-xl px-4 py-3") do
                p(class: "text-[11px] font-semibold text-amber-700 uppercase tracking-wide mb-1") { plain "What to do" }
                p(class: "text-[12.5px] text-amber-900 leading-relaxed") { plain diag[:guidance] }
              end
            elsif is_internal
              p(class: "text-[13px] text-gray-700 leading-relaxed") do
                plain "An internal accounting error occurred while processing this payout. This is usually transient."
              end
              div(class: "bg-amber-50 border border-amber-100 rounded-xl px-4 py-3") do
                p(class: "text-[11px] font-semibold text-amber-700 uppercase tracking-wide mb-1") { plain "What to do" }
                p(class: "text-[12.5px] text-amber-900 leading-relaxed") do
                  plain "Contact support and quote the payout code below. Our team can manually retry the ledger entry."
                end
              end
            end

            div(class: "pt-2 border-t border-gray-100") do
              p(class: TYPE_CAPTION) { plain "Failure code" }
              p(class: "#{TYPE_MONO} mt-0.5 text-red-600 text-[12px]") { plain raw_code }
            end
          end
        end
      end
    end
  end
end
