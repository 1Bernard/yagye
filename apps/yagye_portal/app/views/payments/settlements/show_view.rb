# frozen_string_literal: true

module Payments
  module Settlements
    class ShowView < ApplicationComponent
      include UI::Theme

      def initialize(settlement:)
        @settlement = settlement
      end

      def view_template
        render Layout::Shell.new(
          active_nav: :settlements,
          title:      @settlement.period_label,
          breadcrumbs: [
            { label: "Settlements", url: settlements_path },
            { label: @settlement.period_label }
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
          financials_card
        end
      end

      def right_column
        div(class: "flex flex-col gap-5") do
          state_card
          details_card
        end
      end

      def hero_card
        div(class: "bg-white border border-gray-100 rounded-2xl px-8 py-7") do
          div(class: "flex items-start justify-between mb-5") do
            div do
              p(class: "#{TYPE_CAPTION} mb-1") { plain "Settlement period" }
              p(class: "text-[22px] font-bold text-gray-900") { plain @settlement.period_label }
            end
            render UI::StatusBadge.new(status: @settlement.state)
          end
          div(class: "grid grid-cols-3 gap-[1px] bg-gray-100 rounded-xl overflow-hidden") do
            meta_cell("Expected net", @settlement.formatted_expected_net)
            meta_cell("Reported net", @settlement.formatted_reported_net)
            meta_cell("Variance",     variance_label)
          end
        end
      end

      def financials_card
        div(class: "bg-white border border-gray-100 rounded-2xl overflow-hidden") do
          div(class: "px-6 py-5 border-b border-gray-100") do
            p(class: TYPE_TITLE) { plain "Financial breakdown" }
          end
          render UI::DetailList.new do |list|
            list.row("Expected net",  @settlement.formatted_expected_net)
            list.row("Reported net",  @settlement.formatted_reported_net)
            list.row("Variance") do
              v     = @settlement.variance
              color = v.nil? ? MUTED_TEXT : (v.negative? ? "#dc2626" : "#16a34a")
              span(class: "text-[13px] font-semibold", style: "color:#{color}") { plain variance_label }
            end
            list.row("Item count",   @settlement.item_count&.to_s || "—")
            list.row("Currency",     @settlement.currency)
            list.row("Value date",   @settlement.value_date&.strftime("%d %b %Y") || "—")
          end
        end
      end

      def state_card
        div(class: "bg-white border border-gray-100 rounded-2xl overflow-hidden") do
          div(class: "px-6 py-5 border-b border-gray-100") do
            p(class: TYPE_TITLE) { plain "Reconciliation state" }
          end
          div(class: "px-6 py-5") do
            PortalSettlement::STATES.each_with_index do |s, i|
              state_step(s, @settlement.state == s || past_state?(s), last: i == PortalSettlement::STATES.length - 1)
            end
          end
        end
      end

      def state_step(state, done, last: false)
        color = done ? "#16a34a" : BORDER
        div(class: "flex gap-3") do
          div(class: "flex flex-col items-center flex-shrink-0") do
            div(class: "w-[10px] h-[10px] rounded-full flex-shrink-0 mt-[3px]", style: "background:#{color}")
            div(class: "w-[1px] flex-1 bg-gray-100 mt-1") unless last
          end
          div(class: last ? "" : "pb-[14px]") do
            p(class: (done ? TYPE_BODY_MD : TYPE_CAPTION)) { plain state.humanize }
          end
        end
      end

      def details_card
        div(class: "bg-white border border-gray-100 rounded-2xl overflow-hidden") do
          div(class: "px-6 py-5 border-b border-gray-100") do
            p(class: TYPE_TITLE) { plain "Details" }
          end
          render UI::DetailList.new do |list|
            list.row("Settlement code", @settlement.settlement_code, mono: true)
            list.row("Merchant code",   @settlement.merchant_code || "—", mono: true)
            list.row("Provider code",   @settlement.provider_code || "—", mono: true)
            list.row("Mode",            @settlement.mode&.capitalize || "—")
            list.row("Version",         @settlement.aggregate_version.to_s, mono: true)
            list.row("Last updated",    @settlement.last_applied_at&.strftime("%d %b %Y at %H:%M UTC") || "—")
          end
        end
      end

      def variance_label
        v = @settlement.variance
        return "—" unless v

        formatted = "#{@settlement.currency} #{"%.2f" % (v.abs / 100.0)}"
        v.negative? ? "-#{formatted}" : (v.positive? ? "+#{formatted}" : formatted)
      end

      def past_state?(state)
        order   = PortalSettlement::STATES
        current = @settlement.state
        order.index(state).to_i < order.index(current).to_i
      end
    end
  end
end
