# frozen_string_literal: true

module Payments
  module Reconciliation
    class ShowView < ApplicationComponent
      include UI::Theme

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

      def initialize(recon_break:)
        @break = recon_break
      end

      def view_template
        break_id      = @break["id"].to_s
        short_id      = break_id.first(20)
        severity      = @break["severity"]
        state         = @break["state"]
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
              render UI::StatusBadge.new(severity.presence || "low")
              render UI::StatusBadge.new(state.presence || "detected")
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
        currency   = @break["currency"] || "GHS"
        expected   = @break["expected_amount"].to_i
        actual     = @break["actual_amount"].to_i
        diff       = @break["difference"].to_i
        diff_color = diff < 0 ? RED : GREEN

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
              list.row("Severity") { render UI::StatusBadge.new(severity.presence || "low") }
              list.row("SLA window") do
                if sla_due_at
                  due = Time.parse(sla_due_at) rescue nil
                  if due
                    overdue = state != "resolved" && due < Time.current
                    div(class: "flex flex-col gap-1") do
                      if overdue
                        render UI::StatusBadge.new("overdue")
                      end
                      span(class: TYPE_CAPTION) do
                        plain "Due #{fmt_datetime_utc(due)}"
                      end
                    end
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
            p(class: "#{TYPE_CAPTION} mb-4") do
              plain "Submit an adjustment for dual-control review. A second approver must confirm before the ledger entry is posted."
            end
            a(href: reconciliation_propose_adjustment_modal_path(break_id),
              class: "#{BTN_PRIMARY} w-full justify-center",
              data: { turbo_frame: "modal-frame" }) do
              render UI::Icon.new(:edit, class: ICON_SM)
              plain "Propose adjustment"
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
        fmt_datetime_utc(Time.parse(iso))
      rescue
        iso
      end
    end
  end
end
