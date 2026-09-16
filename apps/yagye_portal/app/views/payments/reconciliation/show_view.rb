# frozen_string_literal: true

module Payments
  module Reconciliation
    class ShowView < ApplicationComponent
      include UI::Theme

      SEVERITY_COLORS = {
        "critical" => { dot: "#dc2626", bg: "bg-red-50",    text: "text-red-700"    },
        "high"     => { dot: "#d97706", bg: "bg-amber-50",  text: "text-amber-700"  },
        "medium"   => { dot: "#2563eb", bg: "bg-blue-50",   text: "text-blue-700"   },
        "low"      => { dot: "#6b7280", bg: "bg-gray-100",  text: "text-gray-600"   }
      }.freeze

      STATE_COLORS = {
        "detected"      => "bg-red-50 text-red-700",
        "triaged"       => "bg-amber-50 text-amber-700",
        "assigned"      => "bg-blue-50 text-blue-700",
        "investigating" => "bg-purple-50 text-purple-700",
        "resolved"      => "bg-green-50 text-green-700",
        "escalated"     => "bg-red-100 text-red-800",
        "written_off"   => "bg-gray-100 text-gray-500"
      }.freeze

      CLASSIFICATION_LABELS = {
        "missing_on_right"   => "Missing on PSP",
        "missing_on_left"    => "Missing on ledger",
        "amount_mismatch"    => "Amount mismatch",
        "duplicate_on_left"  => "Duplicate on ledger",
        "duplicate_on_right" => "Duplicate on PSP",
        "timing_difference"  => "Timing difference",
        "fee_discrepancy"    => "Fee discrepancy",
        "currency_mismatch"  => "Currency mismatch",
        "unknown"            => "Unknown"
      }.freeze

      RESOLUTION_CODES = [
        [ "Adjusted — ledger corrected",        "adjusted"           ],
        [ "Duplicate removed",                  "duplicate_removed"  ],
        [ "Timing — now matched",               "timing_resolved"    ],
        [ "Written off — below threshold",      "written_off"        ],
        [ "External correction by PSP",         "psp_corrected"      ]
      ].freeze

      def initialize(recon_break:)
        @break = recon_break
      end

      def view_template
        break_id      = @break["id"].to_s
        short_id      = break_id.first(20)
        severity      = @break["severity"]
        state         = @break["state"]
        sev_cfg       = SEVERITY_COLORS[severity] || { bg: "bg-gray-100", text: "text-gray-500", dot: "#6b7280" }
        state_cls     = STATE_COLORS[state] || "bg-gray-100 text-gray-500"
        terminal      = %w[resolved written_off].include?(state)

        render Layout::Shell.new(
          active_nav:  :reconciliation,
          title:       "Break #{short_id}",
          breadcrumbs: [
            { label: "Reconciliation", url: reconciliation_path },
            { label: short_id }
          ]
        ) do
          render UI::PageHeader.new(title: "Break #{short_id}") do
            div(class: "flex items-center gap-2") do
              span(class: "inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-[11.5px] font-semibold #{sev_cfg[:bg]} #{sev_cfg[:text]}") do
                span(class: "w-1.5 h-1.5 rounded-full flex-shrink-0", style: "background:#{sev_cfg[:dot]}")
                plain (severity || "—").capitalize
              end
              span(class: "inline-flex items-center px-2.5 py-1 rounded-full text-[11.5px] font-medium #{state_cls}") do
                plain (state || "—").tr("_", " ").capitalize
              end
            end
          end

          render UI::Grid.new(columns: :sidebar) do
            # Left column — detail cards
            div(class: "flex flex-col gap-5") do
              classification_card
              amounts_card
              evidence_card if @break["evidence"].present?
            end

            # Right column — timeline, SLA, action
            div(class: "flex flex-col gap-5") do
              timeline_card
              sla_card
              propose_card(break_id) unless terminal
              resolution_card         if terminal
            end
          end
        end
      end

      private

      def classification_card
        render UI::Card.new do |c|
          c.header("Classification")
          c.body(padding: false) do
            render UI::DetailList.new do |list|
              cls_label = CLASSIFICATION_LABELS[@break["classification"]] ||
                          @break["classification"]&.tr("_", " ")&.capitalize || "—"
              list.row("Type",        cls_label)
              list.row("Left ref",    @break["left_ref"]  || "—", mono: true)
              list.row("Right ref",   @break["right_ref"] || "—", mono: true)
              list.row("Assigned to", @break["assigned_to"] || "Unassigned")
            end
          end
        end
      end

      def amounts_card
        currency = @break["currency"] || "GHS"
        expected = @break["expected_amount"].to_i
        actual   = @break["actual_amount"].to_i
        diff     = @break["difference"].to_i
        diff_color = diff < 0 ? "#dc2626" : "#16a34a"

        render UI::Card.new do |c|
          c.header("Amounts")
          c.body(padding: false) do
            render UI::DetailList.new do |list|
              list.row("Currency",  currency)
              list.row("Expected",  format_money(expected, currency: currency))
              list.row("Actual",    format_money(actual,   currency: currency))
              list.row("Difference") do
                span(class: "text-[13px] font-semibold", style: "color:#{diff_color}") do
                  plain format_money_diff(diff, currency: currency)
                end
              end
            end
          end
        end
      end

      def evidence_card
        evidence = @break["evidence"] || {}
        return if evidence.empty?

        render UI::Card.new do |c|
          c.header("Evidence")
          c.body(padding: false) do
            render UI::DetailList.new do |list|
              evidence.each do |key, value|
                list.row(key.to_s.tr("_", " ").capitalize, value.to_s, mono: value.to_s.match?(/\A[a-z0-9_-]{10,}/i))
              end
            end
          end
        end
      end

      def timeline_card
        detected_str  = format_dt(@break["detected_at"])
        resolved_str  = format_dt(@break["resolved_at"])

        render UI::Card.new do |c|
          c.header("Timeline")
          c.body(padding: false) do
            render UI::DetailList.new do |list|
              list.row("Detected at",  detected_str)
              list.row("Resolved at",  resolved_str || "—")
            end
          end
        end
      end

      def sla_card
        sla_due_at = @break["sla_due_at"]
        state      = @break["state"]
        severity   = @break["severity"]

        render UI::Card.new do |c|
          c.header("SLA")
          c.body(padding: false) do
            render UI::DetailList.new do |list|
              list.row("Severity", (severity || "—").capitalize)
              list.row("SLA window") do
                if sla_due_at
                  due = Time.parse(sla_due_at) rescue nil
                  if due
                    overdue = state != "resolved" && due < Time.current
                    color   = overdue ? "#dc2626" : MUTED_TEXT
                    label   = overdue ? "Overdue (due #{due.strftime("%d %b %Y %H:%M")} UTC)" : "Due #{due.strftime("%d %b %Y %H:%M")} UTC"
                    span(class: "text-[13px] font-medium", style: "color:#{color}") { plain label }
                  else
                    span(class: TYPE_CAPTION) { plain "—" }
                  end
                else
                  span(class: TYPE_CAPTION) { plain "—" }
                end
              end
            end
          end
        end
      end

      def propose_card(break_id)
        render UI::Card.new do |c|
          c.header("Propose adjustment")
          c.body do
            p(class: "#{TYPE_CAPTION} mb-5") do
              plain "Submit an adjustment for dual-control review. A second ops user must approve before the ledger entry is posted."
            end

            form(action: reconciliation_propose_adjustment_path(break_id), method: "post") do
              input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)

              div(class: "flex flex-col gap-3") do
                div do
                  label(class: "block #{TYPE_CAPTION} mb-1") { plain "Adjustment amount (minor units)" }
                  input(type: "number", name: "amount", min: "1", required: true,
                        placeholder: "e.g. 100 = GHS 1.00",
                        class: "w-full h-9 border border-gray-200 rounded-[9px] px-3 text-[13px] text-gray-700 bg-white outline-none focus:ring-1 focus:ring-[#{BRAND}]")
                end

                div do
                  label(class: "block #{TYPE_CAPTION} mb-1") { plain "Direction" }
                  select(name: "direction",
                         class: "w-full h-9 border border-gray-200 rounded-[9px] px-3 text-[13px] text-gray-700 bg-white outline-none cursor-pointer") do
                    option(value: "credit_merchant")  { plain "Credit merchant" }
                    option(value: "debit_merchant")   { plain "Debit merchant"  }
                    option(value: "credit_yagye")     { plain "Credit Yagye"    }
                  end
                end

                div do
                  label(class: "block #{TYPE_CAPTION} mb-1") { plain "Resolution code" }
                  select(name: "resolution_code",
                         class: "w-full h-9 border border-gray-200 rounded-[9px] px-3 text-[13px] text-gray-700 bg-white outline-none cursor-pointer") do
                    RESOLUTION_CODES.each do |(label, value)|
                      option(value: value) { plain label }
                    end
                  end
                end

                div do
                  label(class: "block #{TYPE_CAPTION} mb-1") { plain "Note (optional)" }
                  textarea(name: "resolution_note", rows: "3",
                           placeholder: "Describe the reason for this adjustment…",
                           class: "w-full border border-gray-200 rounded-[9px] px-3 py-2 text-[13px] text-gray-700 bg-white outline-none focus:ring-1 focus:ring-[#{BRAND}] resize-none")
                end

                render UI::Button.new(variant: :primary, type: "submit") do
                  render UI::Icon.new(:check, class: "w-[13px] h-[13px]")
                  plain "Submit for approval"
                end
              end
            end
          end
        end
      end

      def resolution_card
        render UI::Card.new do |c|
          c.header("Resolution")
          c.body(padding: false) do
            render UI::DetailList.new do |list|
              list.row("Code",       @break["resolution_code"]&.tr("_", " ")&.capitalize || "—")
              list.row("Note",       @break["resolution_note"] || "—")
              list.row("Resolved at", format_dt(@break["resolved_at"]) || "—")
            end
          end
        end
      end

      def format_dt(iso)
        return nil if iso.blank?
        Time.parse(iso).strftime("%d %b %Y %H:%M UTC")
      rescue
        iso
      end
    end
  end
end
