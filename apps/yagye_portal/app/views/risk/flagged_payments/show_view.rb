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

      KYC_TIER_BADGE = {
        "tier_1" => STATUS_WARNING,
        "tier_2" => STATUS_NEUTRAL,
        "tier_3" => STATUS_SUCCESS
      }.freeze

      STATE_BADGE = {
        "succeeded" => STATUS_SUCCESS,
        "failed"    => STATUS_FAILED,
        "pending"   => STATUS_WARNING,
        "refunded"  => STATUS_WARNING,
        "cancelled" => STATUS_NEUTRAL
      }.freeze

      SCORE_COLOR = [
        [0.7, RED,   TINT_RED],
        [0.4, AMBER, TINT_AMBER],
        [0.0, GREEN, TINT_GREEN]
      ].freeze

      def initialize(payment: {}, labels: [], customer: nil, history: [], signals: {}, can_dispose: false)
        @payment     = payment
        @labels      = labels
        @customer    = customer
        @history     = history
        @signals     = signals
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
          render UI::PageHeader.new(
            title:    @payment["public_id"] || "Risk Case",
            subtitle: "Flagged payment review"
          )

          hero_card

          render UI::Grid.new(columns: :sidebar_lg) do
            left_column
            right_column
          end

        end
      end

      private

      # ── Hero card ─────────────────────────────────────────────────────────────

      def hero_card
        score    = @payment["risk_score"]
        pct      = score ? (score.to_f * 100).round : 0
        decision = @payment["risk_decision"]
        fg, bg   = score_fg_bg(score)

        div(class: "#{SURFACE_CARD} px-8 py-7 mb-6") do
          div(class: "flex items-start justify-between mb-5") do
            div do
              p(class: "#{TYPE_CAPTION} mb-1") { plain "Transaction amount" }
              p(class: "#{TYPE_AMOUNT} text-gray-900") do
                plain format_money(@payment["amount"].to_i, currency: @payment["currency"] || "GHS")
              end
            end
            decision_chip(decision)
          end

          div(class: "flex items-center gap-3 mb-5") do
            div(class: "flex-1 h-2 rounded-full overflow-hidden",
                style: "background:#{TINT_GRAY}") do
              div(class: "h-full rounded-full",
                  style: "width:#{pct}%;background:#{fg};transition:width 0.5s ease")
            end
            span(class: "#{TYPE_MONO} text-[12.5px] tabular-nums flex-shrink-0",
                 style: "color:#{fg}") { plain score ? "%.2f" % score.to_f : "—" }
            span(class: TYPE_CAPTION) { plain "risk score" }
          end

          div(class: "grid grid-cols-3 gap-[1px] rounded-xl overflow-hidden",
              style: "background:#{BORDER}") do
            meta_cell("Payment ID")   { copyable_mono(@payment["public_id"]) }
            meta_cell("Method")       { plain @payment["method"]&.gsub("_", " ")&.capitalize || "—" }
            meta_cell("Flagged",      fmt_datetime(@payment["risk_flagged_at"]))
          end
        end
      end

      # ── Columns ───────────────────────────────────────────────────────────────

      def left_column
        div(class: "flex flex-col gap-5") do
          customer_card
          signals_card
          details_card
          history_card
        end
      end

      def right_column
        div(class: "flex flex-col gap-5") do
          actions_card if @can_dispose
          labels_card
          sar_card
        end
      end

      # ── Customer ──────────────────────────────────────────────────────────────

      def customer_card
        render UI::Card.new do |c|
          c.header("Customer", icon: :user)
          c.body(padding: false) do
            if @customer
              render UI::DetailList.new do |list|
                list.row("Name")     { p(class: TYPE_BODY_MD) { plain @customer["name"].presence || "—" } }
                list.row("KYC Tier") do
                  tier = @customer["kyc_tier"] || "tier_1"
                  span(class: "#{BADGE} #{KYC_TIER_BADGE.fetch(tier, STATUS_NEUTRAL)}") do
                    plain tier.sub("tier_", "Tier ")
                  end
                end
                list.row("Phone",    @customer["phone"].presence || "—")
                list.row("Email",    @customer["email"].presence || "—")
                list.row("Customer ID", stacked: true) { copyable_mono(@customer["public_id"]) }
                list.row("Customer since", fmt_date(@customer["customer_since"]))
              end
            else
              div(class: "px-6 py-5 text-center") do
                p(class: TYPE_CAPTION) { plain "No customer linked to this transaction." }
                p(class: "#{TYPE_CAPTION} mt-1", style: "color:#{SUBTLE_TEXT}") do
                  plain "Guest checkout or customer data not yet synced."
                end
              end
            end
          end
        end
      end

      # ── Risk signals ──────────────────────────────────────────────────────────

      def signals_card
        return unless @signals.any?

        count_7d  = @signals["tx_count_7d"].to_i
        count_30d = @signals["tx_count_30d"].to_i
        avg       = @signals["avg_amount_30d"].to_i
        ratio     = @signals["amount_vs_avg"]
        unusual   = @signals["unusual_method"]
        new_cust  = @signals["new_customer"]

        render UI::Card.new do |c|
          c.header("Risk Signals", icon: :alert_triangle)
          c.body(padding: false) do
            div(class: "grid grid-cols-2 gap-[1px]", style: "background:#{BORDER}") do
              velocity_stat("7-day velocity",  count_7d,  alert: count_7d >= 5)
              velocity_stat("30-day velocity", count_30d, alert: count_30d >= 15)
            end
            div do
              indicator_row("New customer",
                            new_cust ? "Yes — first transaction" : "No — returning",
                            alert: new_cust)
              indicator_row("Payment method",
                            unusual ? "Unusual for this customer" : "Consistent with history",
                            alert: unusual)
              if ratio
                indicator_row("Amount vs 30-day avg",
                              "#{ratio}× average (avg #{format_money(avg, currency: @payment["currency"] || "GHS")})",
                              alert: ratio.to_f >= 3.0)
              end
            end
          end
        end
      end

      # ── Payment details ───────────────────────────────────────────────────────

      def details_card
        render UI::Card.new do |c|
          c.header("Payment details")
          c.body(padding: false) do
            render UI::DetailList.new do |list|
              list.row("Payment ID",  stacked: true) { copyable_mono(@payment["public_id"]) }
              list.row("Merchant ID", stacked: true) { copyable_mono(@payment["merchant_id"]) }
              list.row("Method",   @payment["method"]&.gsub("_", " ")&.capitalize || "—")
              list.row("State")    { render UI::StatusBadge.new(@payment["state"] || "unknown") }
              list.row("Currency", @payment["currency"] || "—")
              list.row("Flagged at", fmt_datetime_utc(@payment["risk_flagged_at"]))
            end
          end
        end
      end

      # ── Payment history ───────────────────────────────────────────────────────

      def history_card
        render UI::Card.new do |c|
          c.header("Customer payment history")
          c.body(padding: @history.empty?) do
            if @history.empty?
              div(class: "py-4 text-center") do
                p(class: TYPE_CAPTION) do
                  plain @customer ? "No previous transactions found for this customer." \
                                  : "No customer linked — history unavailable."
                end
              end
            else
              div(class: "overflow-x-auto") do
                table(class: "w-full") do
                  thead do
                    tr(class: "border-b", style: "border-color:#{BORDER}") do
                      %w[Date Amount Method State Risk].each do |h|
                        th(class: TABLE_TH) { plain h }
                      end
                    end
                  end
                  tbody do
                    @history.each do |p|
                      state_cls = STATE_BADGE[p["state"]] || STATUS_NEUTRAL
                      score     = p["risk_score"]
                      fg, _     = score_fg_bg(score)
                      tr(class: TABLE_ROW) do
                        td(class: TABLE_CELL) { span(class: TYPE_CAPTION) { plain fmt_date(p["inserted_at"]) } }
                        td(class: TABLE_CELL) do
                          span(class: "text-[13px] font-semibold tabular-nums text-gray-800") do
                            plain format_money(p["amount"].to_i, currency: p["currency"] || "GHS")
                          end
                        end
                        td(class: TABLE_CELL) { span(class: TYPE_CAPTION) { plain p["method"]&.gsub("_", " ")&.capitalize || "—" } }
                        td(class: TABLE_CELL) { span(class: "#{BADGE} #{state_cls}") { plain p["state"]&.capitalize || "—" } }
                        td(class: TABLE_CELL) do
                          span(class: "#{TYPE_MONO} text-[11.5px]", style: score ? "color:#{fg}" : "") do
                            plain score ? "%.2f" % score.to_f : "—"
                          end
                        end
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end

      # ── Disposition form ──────────────────────────────────────────────────────

      def actions_card
        render UI::Card.new do |c|
          c.header("Disposition Case", icon: :check_circle)
          c.body do
            div(id: "disposition-form") do
              form(action: dispose_risk_flagged_payment_path(@payment["id"]), method: "post",
                   class: "flex flex-col gap-3") do
                input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
                div do
                  label(for: "case_label", class: "block #{TYPE_LABEL} mb-1.5") { plain "Label" }
                  select(id: "case_label", name: "label", required: true, class: SELECT_FIELD) do
                    option(value: "") { plain "Select label…" }
                    LABEL_OPTIONS.each do |lbl|
                      option(value: lbl) { plain lbl.tr("_", " ").capitalize }
                    end
                  end
                end
                div do
                  label(for: "case_note", class: "block #{TYPE_LABEL} mb-1.5") { plain "Note (optional)" }
                  textarea(id: "case_note", name: "note", rows: "3",
                           placeholder: "Add context for model training…",
                           class: TEXTAREA_FIELD)
                end
                button(type: "submit", class: "#{BTN_PRIMARY} w-full justify-center") do
                  plain "Submit Disposition"
                end
              end
            end
          end
        end
      end

      # ── Disposition history ───────────────────────────────────────────────────

      def labels_card
        render UI::Card.new do |c|
          c.header("Disposition History")
          c.body(padding: @labels.empty?) do
            if @labels.empty?
              p(class: TYPE_CAPTION) { plain "No dispositions yet." }
            else
              div(class: "divide-y", style: "border-color:#{BORDER}") do
                @labels.each do |lbl|
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
                          p(class: "#{TYPE_CAPTION} mt-1 italic", style: "color:#{SUBTLE_TEXT}") do
                            plain lbl["note"]
                          end
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

      # ── SAR export ────────────────────────────────────────────────────────────

      def sar_card
        render UI::Card.new do |c|
          c.header("Compliance Export", icon: :file)
          c.body do
            p(class: "#{TYPE_CAPTION} mb-3") do
              plain "Generate a Suspicious Activity Report for this case."
            end
            a(href: sar_risk_flagged_payment_path(@payment["id"]),
              class: "#{BTN_SECONDARY} w-full justify-center",
              target: "_blank", rel: "noopener",
              data: { turbo: false }) do
              render UI::Icon.new(:download, class: ICON_SM)
              plain "Export SAR"
            end
          end
        end
      end

      # ── Helpers ───────────────────────────────────────────────────────────────

      def decision_chip(decision)
        badge_class = DECISION_BADGE[decision] || STATUS_NEUTRAL
        span(class: "#{BADGE} #{badge_class}") { plain decision&.capitalize || "—" }
      end

      def meta_cell(label, value = nil, &block)
        div(class: "px-5 py-4 bg-white") do
          p(class: TYPE_CAPTION) { plain label }
          if block
            div(class: "mt-[3px]") { yield }
          else
            p(class: "#{TYPE_BODY_MD} mt-[3px]") { plain value.to_s }
          end
        end
      end

      def velocity_stat(label, count, alert: false)
        num_color = alert ? RED : INK
        div(class: "px-5 py-4 bg-white") do
          p(class: "text-[26px] font-bold tabular-nums leading-none",
            style: "color:#{num_color}") { plain count.to_s }
          p(class: "#{TYPE_CAPTION} mt-1") { plain label }
        end
      end

      def indicator_row(label, value, alert: false)
        dot_color = alert ? RED   : GREEN
        val_color = alert ? RED   : BODY_TEXT
        div(class: "flex items-center justify-between gap-3 px-5 py-3") do
          div(class: "flex items-center gap-2.5") do
            div(class: "w-2 h-2 rounded-full flex-shrink-0",
                style: "background:#{dot_color}")
            span(class: TYPE_BODY_MD) { plain label }
          end
          span(class: "text-[12.5px] font-medium text-right",
               style: "color:#{val_color}") { plain value }
        end
      end

      def score_fg_bg(score)
        return [SUBTLE_TEXT, SURFACE] unless score
        row = SCORE_COLOR.find { |threshold, _, _| score.to_f >= threshold }
        row ? [row[1], row[2]] : [SUBTLE_TEXT, SURFACE]
      end
    end
  end
end
