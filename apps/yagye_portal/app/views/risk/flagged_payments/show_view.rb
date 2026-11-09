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
          title:      "Risk Case",
          breadcrumbs: [
            { label: "Risk & Fraud", path: risk_flagged_payments_path },
            { label: @payment["public_id"] || "Case" }
          ]
        ) do
          render UI::PageHeader.new(
            title:    @payment["public_id"] || "Risk Case",
            subtitle: "Transaction risk assessment and analyst disposition."
          )

          div(class: "flex justify-end mb-4") do
            a(href: sar_risk_flagged_payment_path(@payment["id"]),
              class: "inline-flex items-center gap-1.5 px-3 py-1.5 rounded-xl " \
                     "border border-gray-200 bg-white text-[12px] font-medium text-gray-600 " \
                     "hover:bg-gray-50 transition-colors no-underline") do
              span(style: "display:flex;width:13px;height:13px;flex-shrink:0") do
                render UI::Icon.new(:file, class: "w-full h-full")
              end
              plain "Export SAR"
            end
          end

          payment_detail_card
          disposition_card if @can_dispose
          labels_history
        end
      end

      private

      def payment_detail_card
        decision = @payment["risk_decision"]
        score    = @payment["risk_score"]

        div(class: "#{SURFACE_CARD} p-5 mb-4") do
          p(class: "text-[11px] font-semibold uppercase tracking-wide text-gray-400 mb-3") do
            plain "Payment Details"
          end

          render UI::Grid.new(columns: 4) do
            stat_cell("Amount",
                      format_money(@payment["amount"].to_i),
                      icon: :wallet, color: GREEN, tint: TINT_GREEN)
            stat_cell("Currency", @payment["currency"] || "—",
                      icon: :globe, color: PURPLE, tint: TINT_PURPLE)
            stat_cell("Method",   @payment["method"]&.upcase || "—",
                      icon: :smartphone, color: AMBER, tint: TINT_AMBER)
            stat_cell("State",    @payment["state"]&.capitalize || "—",
                      icon: :check_circle, color: GREEN, tint: TINT_GREEN)
          end

          div(class: "mt-4 pt-4 border-t border-gray-50 flex items-center gap-6") do
            div do
              p(class: "text-[10.5px] text-gray-400 font-medium uppercase tracking-wide") { plain "Risk Score" }
              p(class: "text-[18px] font-bold tabular-nums text-gray-900 mt-[2px]") do
                plain score ? format("%.4f", score.to_f) : "—"
              end
            end

            div do
              p(class: "text-[10.5px] text-gray-400 font-medium uppercase tracking-wide") { plain "Decision" }
              div(class: "mt-[4px]") do
                badge_class = DECISION_BADGE[decision] || STATUS_NEUTRAL
                span(class: "#{BADGE} #{badge_class}") { plain decision&.capitalize || "—" }
              end
            end

            div do
              p(class: "text-[10.5px] text-gray-400 font-medium uppercase tracking-wide") { plain "Flagged At" }
              p(class: "text-[12.5px] text-gray-700 mt-[2px]") do
                plain fmt_datetime(@payment["risk_flagged_at"])
              end
            end
          end
        end
      end

      def disposition_card
        div(class: "#{SURFACE_CARD} p-5 mb-4") do
          p(class: "text-[11px] font-semibold uppercase tracking-wide text-gray-400 mb-3") do
            plain "Disposition Case"
          end

          form(action: dispose_risk_flagged_payment_path(@payment["id"]), method: "post",
               class: "space-y-3") do
            input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)

            div do
              label(for: "label", class: "block text-[12px] font-medium text-gray-700 mb-1") do
                plain "Label"
              end
              select(id: "label", name: "label", required: true,
                     class: "block w-full max-w-[240px] rounded-xl border border-gray-200 " \
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
              textarea(id: "note", name: "note", rows: "2",
                       placeholder: "Add context for model training…",
                       class: "block w-full max-w-[480px] rounded-xl border border-gray-200 " \
                              "px-3 py-2 text-[13px] text-gray-700 bg-white resize-none " \
                              "focus:outline-none focus:border-brand/50 focus:ring-2 focus:ring-brand/10")
            end

            button(type: "submit",
                   class: "px-4 py-2 rounded-xl bg-brand text-white text-[12.5px] font-medium " \
                          "hover:bg-brand/90 transition-colors") do
              plain "Submit Disposition"
            end
          end
        end
      end

      def labels_history
        div(class: "#{SURFACE_CARD} p-5") do
          p(class: "text-[11px] font-semibold uppercase tracking-wide text-gray-400 mb-3") do
            plain "Disposition History"
          end

          if @labels.empty?
            p(class: TYPE_CAPTION) { plain "No dispositions yet." }
          else
            div(class: "space-y-2") do
              @labels.each do |lbl|
                badge_class = LABEL_BADGE[lbl["label"]] || STATUS_NEUTRAL
                div(class: "flex items-start justify-between py-2 border-b border-gray-50 last:border-0") do
                  div do
                    span(class: "#{BADGE} #{badge_class} mr-2") { plain lbl["label"]&.tr("_", " ")&.capitalize }
                    span(class: TYPE_CAPTION) { plain "by #{lbl['labelled_by']}" }
                    if lbl["note"].present?
                      p(class: "#{TYPE_CAPTION} mt-1 text-gray-400 italic") { plain lbl["note"] }
                    end
                  end
                  span(class: TYPE_CAPTION) { plain fmt_datetime(lbl["inserted_at"]) }
                end
              end
            end
          end
        end
      end
    end
  end
end
