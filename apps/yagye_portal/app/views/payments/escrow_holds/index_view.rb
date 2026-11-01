# frozen_string_literal: true

module Payments
  module EscrowHolds
    class IndexView < ApplicationComponent
      include UI::Theme

      STATE_TABS = [
        { key: nil,         label: "All"       },
        { key: "held",      label: "Held"      },
        { key: "disputed",  label: "Disputed"  },
        { key: "released",  label: "Released"  },
        { key: "refunded",  label: "Refunded"  }
      ].freeze

      STATE_BADGE = {
        "held"      => STATUS_PENDING,
        "disputed"  => STATUS_WARNING,
        "released"  => STATUS_SUCCESS,
        "refunded"  => STATUS_NEUTRAL
      }.freeze

      def initialize(holds: [], state_filter: nil)
        @holds        = holds
        @state_filter = state_filter
      end

      def view_template
        render Layout::Shell.new(
          active_nav:  :escrow_holds,
          title:       "Escrow Holds",
          breadcrumbs: [ { label: "Escrow Holds" } ]
        ) do
          stat_band
          tab_bar
          holds_table
        end
      end

      private

      def stat_band
        all    = @holds
        render UI::Grid.new(columns: 4) do
          stat_cell("Held",     all.count { |h| h["state"] == "held"     }.to_s, icon: :lock,         color: AMBER, tint: TINT_AMBER)
          stat_cell("Disputed", all.count { |h| h["state"] == "disputed" }.to_s, icon: :flag,         color: RED,   tint: TINT_RED)
          stat_cell("Released", all.count { |h| h["state"] == "released" }.to_s, icon: :check_circle, color: GREEN, tint: TINT_GREEN)
          stat_cell("Refunded", all.count { |h| h["state"] == "refunded" }.to_s, icon: :refresh,      color: SLATE, tint: TINT_NEUTRAL)
        end
      end

      def tab_bar
        render UI::Tabs.new do |t|
          STATE_TABS.each do |tab|
            t.tab tab[:label],
                  href:   escrow_holds_path(state: tab[:key]),
                  active: @state_filter == tab[:key]
          end
        end
      end

      def holds_table
        render UI::Datatable.new(records: @holds, empty_message: "No escrow holds found.") do |t|
          t.header { toolbar_content }

          t.column("Hold ID",    class: "font-mono text-[11.5px]") { |h| plain h["public_id"].to_s }
          t.column("Payment",   class: "font-mono text-[11.5px]") { |h| plain h["payment_public_id"].to_s }
          t.column("Amount")    { |h| plain format_money(h["amount"].to_i, currency: h["currency"] || "GHS") }
          t.column("State")     { |h| state_badge(h["state"]) }
          t.column("Auto-release") do |h|
            if h["release_at"]
              plain fmt_datetime(parse_ts(h["release_at"]))
            else
              span(class: "text-[11px] text-gray-400") { plain "—" }
            end
          end
          t.column("Created")   { |h| plain fmt_date(parse_ts(h["inserted_at"])) }

          t.actions do |h|
            a(href: escrow_hold_path(h["public_id"]), class: DROPDOWN_ITEM) do
              render UI::Icon.new(:eye, class: ICON_SM)
              plain "View"
            end
          end
        end
      end

      def toolbar_content
        form(action: escrow_holds_path, method: "get") do
          input(type: "hidden", name: "state", value: @state_filter) if @state_filter
          div(class: FILTER_SEARCH_WRAP) do
            span(class: "flex w-[13px] h-[13px] text-gray-400 flex-shrink-0") do
              render UI::Icon.new(:search, class: "w-full h-full")
            end
            input(type: "search", name: "q", placeholder: "Search hold or payment ID…", class: FILTER_SEARCH_INPUT)
          end
        end
      end

      def parse_ts(str)
        str.present? ? Time.parse(str.to_s) : nil
      rescue ArgumentError
        nil
      end

      def state_badge(state)
        cls = STATE_BADGE.fetch(state.to_s, STATUS_NEUTRAL)
        span(class: "#{cls} #{BADGE}") { plain state.to_s.capitalize }
      end
    end
  end
end
