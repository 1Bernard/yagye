# frozen_string_literal: true

module Risk
  module FlaggedPayments
    class IndexView < ApplicationComponent
      include UI::Theme

      TABS = [
        { key: "review", label: "For Review" },
        { key: "block",  label: "Blocked" }
      ].freeze

      DECISION_BADGE = {
        "allow"  => STATUS_SUCCESS,
        "review" => STATUS_WARNING,
        "block"  => STATUS_FAILED
      }.freeze

      # Risk score thresholds → color
      SCORE_COLOR = [
        [ 0.7, RED,   "#fef2f2" ],
        [ 0.4, AMBER, "#fffbeb" ],
        [ 0.0, GREEN, "#f0fdf4" ]
      ].freeze

      def initialize(tab: "review", records: [], has_more: false, next_cursor: nil, can_dispose: false)
        @tab         = tab
        @records     = records
        @has_more    = has_more
        @next_cursor = next_cursor
        @can_dispose = can_dispose
      end

      def view_template
        render Layout::Shell.new(
          active_nav: :risk,
          title:      "Risk & Fraud",
          breadcrumbs: [ { label: "Risk & Fraud" } ]
        ) do
          render UI::PageHeader.new(
            title:    "Risk & Fraud",
            subtitle: "Flagged payments requiring analyst review."
          )

          tab_bar
          payments_list
        end
      end

      private

      def tab_bar
        render UI::Tabs.new do |t|
          TABS.each do |tab|
            t.tab tab[:label],
                  href:   risk_flagged_payments_path(tab: tab[:key]),
                  active: @tab == tab[:key]
          end
        end
      end

      def payments_list
        can_dispose   = @can_dispose
        score_color   = SCORE_COLOR

        render UI::Datatable.new(records: @records, empty_message: "No flagged payments in this queue.") do |t|
          t.column("Payment ID") do |r|
            a(href: risk_flagged_payment_path(r["id"]),
              class: "#{TYPE_MONO} text-brand hover:underline") do
              plain r["public_id"]
            end
          end

          t.column("Amount") do |r|
            span(class: "text-[13px] font-semibold text-gray-800 tabular-nums") do
              plain format_money(r["amount"].to_i, currency: r["currency"] || "GHS")
            end
          end

          t.column("Method") do |r|
            span(class: TYPE_CAPTION) { plain r["method"]&.gsub("_", " ")&.capitalize || "—" }
          end

          t.column("Risk Score") do |r|
            score = r["risk_score"]
            if score
              pct = (score.to_f * 100).round
              _, color, bg = score_color.find { |threshold, _, _| score.to_f >= threshold }
              color ||= "#0a7cff"
              bg    ||= "#f9fafb"
              div(class: "flex items-center gap-2") do
                div(class: "w-16 h-1.5 rounded-full overflow-hidden flex-shrink-0",
                    style: "background:#{bg}") do
                  div(class: "h-full rounded-full",
                      style: "width:#{pct}%;background:#{color}")
                end
                span(class: "#{TYPE_MONO} text-[11.5px]", style: "color:#{color}") do
                  plain "%.2f" % score.to_f
                end
              end
            else
              span(class: TYPE_CAPTION) { plain "—" }
            end
          end

          t.column("Decision") do |r|
            decision = r["risk_decision"]
            badge_class = DECISION_BADGE[decision] || STATUS_NEUTRAL
            span(class: "#{BADGE} #{badge_class}") { plain decision&.capitalize || "—" }
          end

          t.column("Flagged") do |r|
            span(class: TYPE_CAPTION) { plain fmt_datetime(r["risk_flagged_at"]) }
          end

          t.actions do |r|
            a(href: risk_flagged_payment_path(r["id"]), class: DROPDOWN_ITEM) do
              render UI::Icon.new(:eye, class: ICON_SM)
              plain "Review case"
            end
          end
        end

        if @has_more && @next_cursor
          div(class: "mt-4 flex justify-center") do
            a(href: risk_flagged_payments_path(tab: @tab, after: @next_cursor),
              class: "px-4 py-2 text-[12.5px] font-medium text-brand border border-brand/30 " \
                     "rounded-xl hover:bg-brand/5 transition-colors") do
              plain "Load more"
            end
          end
        end
      end

    end
  end
end
