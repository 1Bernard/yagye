# frozen_string_literal: true

module Payments
  module EscrowHolds
    class ShowView < ApplicationComponent
      include UI::Theme

      STATE_BADGE = {
        "held"      => STATUS_PENDING,
        "disputed"  => STATUS_WARNING,
        "released"  => STATUS_SUCCESS,
        "refunded"  => STATUS_NEUTRAL
      }.freeze

      def initialize(hold:)
        @hold = hold
      end

      def view_template
        render Layout::Shell.new(
          active_nav:  :escrow_holds,
          title:       @hold["public_id"].to_s,
          breadcrumbs: [
            { label: "Escrow Holds", href: escrow_holds_path },
            { label: @hold["public_id"].to_s }
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
          payment_card
          timeline_card
        end
      end

      def hero_card
        div(class: "#{SURFACE_CARD} px-8 py-7") do
          div(class: "flex items-start justify-between mb-5") do
            div do
              p(class: "#{TYPE_CAPTION} mb-1") { plain "Held amount" }
              p(class: "#{TYPE_AMOUNT} text-gray-900") { plain format_money(@hold["amount"].to_i, currency: @hold["currency"] || "GHS") }
            end
            div(class: "flex flex-col items-end gap-2") do
              state_badge_el(@hold["state"])
              if @hold["state"] == "disputed"
                span(class: "#{BADGE} #{STATUS_WARNING}") { plain "Awaiting ops review" }
              end
            end
          end
          div(class: "grid grid-cols-3 gap-[1px] bg-gray-100 rounded-xl overflow-hidden") do
            meta_cell("Hold ID",   @hold["public_id"].to_s, mono: true)
            meta_cell("Payment",   @hold["payment_public_id"].to_s, mono: true)
            meta_cell("Currency",  @hold["currency"].to_s)
          end
        end
      end

      def payment_card
        render UI::Card.new do |c|
          c.header("Hold details", icon: :lock)
          c.body(padding: false) do
            render UI::DetailList.new do |list|
              list.row("State")          { state_badge_el(@hold["state"]) }
              list.row("Auto-release",   auto_release_label)
              list.row("Dispute window") do
                if @hold["dispute_window_ends_at"]
                  plain fmt_datetime(parse_ts(@hold["dispute_window_ends_at"]))
                else
                  plain "—"
                end
              end
              list.row("Confirmed at") do
                if @hold["buyer_confirmed_at"]
                  plain fmt_datetime(parse_ts(@hold["buyer_confirmed_at"]))
                else
                  plain "—"
                end
              end
              list.row("Released at") do
                if @hold["released_at"]
                  plain fmt_datetime(parse_ts(@hold["released_at"]))
                else
                  plain "—"
                end
              end
              list.row("Created", fmt_datetime(parse_ts(@hold["inserted_at"])))
            end
          end
        end
      end

      def timeline_card
        events = build_timeline
        render UI::Card.new do |c|
          c.header("Activity", icon: :clock)
          c.body do
            div(class: "flex flex-col") do
              events.each_with_index do |(label, at, color), i|
                last = i == events.length - 1
                div(class: "flex gap-[14px]") do
                  div(class: "flex flex-col items-center flex-shrink-0") do
                    div(class: "w-[10px] h-[10px] rounded-full flex-shrink-0 mt-[3px]", style: "background:#{color}")
                    div(class: "w-[1px] flex-1 bg-gray-100 mt-1") unless last
                  end
                  div(class: last ? "" : "pb-[18px]") do
                    p(class: TYPE_BODY_MD) { plain label }
                    p(class: "#{TYPE_CAPTION} mt-px") { plain at.to_s }
                  end
                end
              end
            end
          end
        end
      end

      def build_timeline
        events = []
        events << [ "Escrow hold created", fmt_datetime(parse_ts(@hold["inserted_at"])), BRAND ]
        events << [ "Dispute opened by buyer", fmt_datetime(parse_ts(@hold["dispute_opened_at"])), AMBER ] if @hold["dispute_opened_at"]
        events << [ "Buyer confirmed receipt", fmt_datetime(parse_ts(@hold["buyer_confirmed_at"])), GREEN ] if @hold["buyer_confirmed_at"]
        events << [ "Funds released to merchant", fmt_datetime(parse_ts(@hold["released_at"])), GREEN ] if @hold["released_at"] && @hold["state"] == "released"
        events << [ "Funds refunded to buyer", fmt_datetime(parse_ts(@hold["released_at"])), SLATE ] if @hold["released_at"] && @hold["state"] == "refunded"
        events
      end

      def right_column
        div(class: "flex flex-col gap-4") do
          status_card
          dispute_card if @hold["state"] == "disputed" && current_user&.internal_staff?
        end
      end

      def status_card
        render UI::Card.new do |c|
          c.header("Status")
          c.body(padding: false) do
            render UI::DetailList.new do |list|
              list.row("State") { state_badge_el(@hold["state"]) }
              list.row("Auto-release at", auto_release_label)
              if @hold["dispute_note"].present?
                list.row("Buyer note") do
                  p(class: "text-[12.5px] text-gray-700 whitespace-pre-wrap") { plain @hold["dispute_note"].to_s }
                end
              end
            end
          end
        end
      end

      def dispute_card
        render UI::Card.new do |c|
          c.header("Ops: Resolve dispute")
          c.body do
            div(class: "flex flex-col gap-4") do
              p(class: "text-[12.5px] text-gray-600") do
                plain "The buyer has raised a dispute. Review the context and choose an outcome: release funds to the merchant or refund the buyer."
              end
              if @hold["dispute_note"].present?
                div(class: "bg-gray-50 rounded-xl px-4 py-3") do
                  p(class: "#{TYPE_CAPTION} mb-1 font-medium") { plain "Buyer's note" }
                  p(class: "text-[12.5px] text-gray-700 whitespace-pre-wrap") { plain @hold["dispute_note"].to_s }
                end
              end

              form(action: resolve_dispute_escrow_hold_path(@hold["public_id"]), method: "post") do
                input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
                div(class: "flex flex-col gap-3") do
                  div(class: "flex flex-col gap-1.5") do
                    label(class: TEXT_LABEL, for: "note") { plain "Resolution note" }
                    textarea(name: "note", id: "note", rows: "3",
                             placeholder: "Brief explanation for the record…",
                             class: TEXTAREA_FIELD)
                  end
                  div(class: "flex gap-2") do
                    button(type: "submit", name: "outcome", value: "release",
                           class: "#{BTN_SECONDARY} flex-1 justify-center") do
                      plain "Release to merchant"
                    end
                    button(type: "submit", name: "outcome", value: "refund",
                           class: "#{BTN_DANGER} flex-1 justify-center") do
                      plain "Refund buyer"
                    end
                  end
                end
              end
            end
          end
        end
      end

      # ── Helpers ─────────────────────────────────────────────────────────────

      def state_badge_el(state)
        cls = STATE_BADGE.fetch(state.to_s, STATUS_NEUTRAL)
        span(class: "#{cls} #{BADGE}") { plain state.to_s.capitalize }
      end

      def parse_ts(str)
        str.present? ? Time.parse(str.to_s) : nil
      rescue ArgumentError
        nil
      end

      def auto_release_label
        return "—" unless @hold["release_at"]
        fmt_datetime(parse_ts(@hold["release_at"]))
      end
    end
  end
end
