# frozen_string_literal: true

module Risk
  module FlaggedPayments
    class ShowView < ApplicationComponent
      include UI::Theme

      LABEL_OPTIONS = %w[confirmed_fraud false_positive suspicious legitimate].freeze

      LABEL_BADGE = {
        "confirmed_fraud" => STATUS_FAILED,
        "false_positive"  => STATUS_SUCCESS,
        "suspicious"      => STATUS_WARNING,
        "legitimate"      => STATUS_NEUTRAL
      }.freeze

      DECISION_BADGE = {
        "allow"  => STATUS_SUCCESS,
        "review" => STATUS_WARNING,
        "block"  => STATUS_FAILED
      }.freeze

      def initialize(payment: {}, labels: [], can_dispose: false)
        @payment     = payment
        @labels      = labels
        @can_dispose = can_dispose
      end

      def view_template
        render Layout::Shell.new(
          active_nav: :risk,
          title:      @payment["public_id"] || "Risk Case",
          breadcrumbs: [
            { label: "Risk & Fraud", path: risk_flagged_payments_path },
            { label: @payment["public_id"] || "Case" }
          ]
        ) do
          render UI::Grid.new(columns: :sidebar_lg) do
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
          actions_card if @can_dispose
          history_card
          sar_card
        end
      end

      # ── Hero card (mirrors amount_card in payment show) ───────────────────

      def hero_card
        decision = @payment["risk_decision"]
        score    = @payment["risk_score"]

        div(class: "#{SURFACE_CARD} px-8 py-7") do
          div(class: "flex items-start justify-between mb-5") do
            div do
              p(class: "#{TYPE_CAPTION} mb-1") { plain "Transaction amount" }
              p(class: "#{TYPE_AMOUNT} text-gray-900") do
                plain format_money(@payment["amount"].to_i, currency: @payment["currency"] || "GHS")
              end
            end
            decision_badge(decision)
          end

          div(class: "grid grid-cols-3 gap-[1px] bg-gray-100 rounded-xl overflow-hidden mb-3") do
            meta_cell("Payment ID") { copyable_mono(@payment["public_id"]) }
            meta_cell("Risk Score") do
              p(class: "text-[13px] font-bold tabular-nums text-gray-900") do
                plain score ? "%.4f" % score.to_f : "—"
              end
            end
            meta_cell("Flagged", fmt_datetime(@payment["risk_flagged_at"]))
          end
        end
      end

      # ── Payment details card ──────────────────────────────────────────────

      def details_card
        render UI::Card.new do |c|
          c.header("Payment details")
          c.body(padding: false) do
            render UI::DetailList.new do |list|
              list.row("Payment ID", stacked: true) { copyable_mono(@payment["public_id"]) }
              list.row("Merchant ID", stacked: true) { copyable_mono(@payment["merchant_id"]) }
              list.row("Method",   @payment["method"]&.gsub("_", " ")&.capitalize || "—")
              list.row("State")    { render UI::StatusBadge.new(@payment["state"] || "unknown") }
              list.row("Currency", @payment["currency"] || "—")
              list.row("Flagged at", fmt_datetime_utc(@payment["risk_flagged_at"]))
            end
          end
        end
      end

      # ── Disposition form (right sidebar) ─────────────────────────────────

      def actions_card
        render UI::Card.new do |c|
          c.header("Disposition Case")
          c.body do
            form(action: dispose_risk_flagged_payment_path(@payment["id"]), method: "post",
                 class: "space-y-3") do
              input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)

              div do
                label(for: "label", class: "block text-[12px] font-medium text-gray-700 mb-1") do
                  plain "Label"
                end
                select(id: "label", name: "label", required: true,
                       class: "block w-full rounded-xl border border-gray-200 " \
                              "px-3 py-2 text-[13px] text-gray-700 bg-white focus:outline-none " \
                              "focus:border-brand/50 focus:ring-2 focus:ring-brand/10") do
                  option(value: "") { plain "Select label…" }
                  LABEL_OPTIONS.each do |lbl|
                    option(value: lbl) { plain lbl.tr("_", " ").capitalize }
                  end
                end
              end

              div do
                label(for: "note", class: "block text-[12px] font-medium text-gray-700 mb-1") do
                  plain "Note (optional)"
                end
                textarea(id: "note", name: "note", rows: "3",
                         placeholder: "Add context for model training…",
                         class: "block w-full rounded-xl border border-gray-200 " \
                                "px-3 py-2 text-[13px] text-gray-700 bg-white resize-none " \
                                "focus:outline-none focus:border-brand/50 focus:ring-2 focus:ring-brand/10")
              end

              button(type: "submit",
                     class: "#{BTN_PRIMARY} w-full justify-center") do
                plain "Submit Disposition"
              end
            end
          end
        end
      end

      # ── Disposition history ───────────────────────────────────────────────

      def history_card
        render UI::Card.new do |c|
          c.header("Disposition History")
          c.body(padding: @labels.empty?) do
            if @labels.empty?
              p(class: TYPE_CAPTION) { plain "No dispositions yet." }
            else
              div(class: "divide-y divide-gray-50") do
                @labels.each_with_index do |lbl, i|
                  badge_class = LABEL_BADGE[lbl["label"]] || STATUS_NEUTRAL
                  div(class: "px-5 py-[11px]") do
                    div(class: "flex items-start justify-between gap-3") do
                      div(class: "flex-1 min-w-0") do
                        div(class: "flex items-center gap-2 flex-wrap") do
                          span(class: "#{BADGE} #{badge_class}") do
                            plain lbl["label"]&.tr("_", " ")&.capitalize
                          end
                          span(class: TYPE_CAPTION) { plain "by #{lbl['labelled_by']}" }
                        end
                        if lbl["note"].present?
                          p(class: "#{TYPE_CAPTION} mt-1 text-gray-400 italic") { plain lbl["note"] }
                        end
                      end
                      span(class: "#{TYPE_CAPTION} flex-shrink-0") do
                        plain fmt_datetime(lbl["inserted_at"])
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end

      # ── SAR export card ───────────────────────────────────────────────────

      def sar_card
        render UI::Card.new do |c|
          c.header("Compliance Export")
          c.body do
            p(class: "#{TYPE_CAPTION} mb-3") do
              plain "Generate a Suspicious Activity Report for this case."
            end
            a(href: sar_risk_flagged_payment_path(@payment["id"]),
              class: "#{BTN_SECONDARY} w-full justify-center",
              data: { turbo: false }) do
              span(style: "display:flex;width:13px;height:13px;flex-shrink:0") do
                render UI::Icon.new(:file, class: "w-full h-full")
              end
              plain "Export SAR"
            end
          end
        end
      end

      # ── Helpers ───────────────────────────────────────────────────────────

      def decision_badge(decision)
        badge_class = DECISION_BADGE[decision] || STATUS_NEUTRAL
        span(class: "#{BADGE} #{badge_class} text-[12.5px] px-3 py-1") do
          plain decision&.capitalize || "—"
        end
      end
    end
  end
end
