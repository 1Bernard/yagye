# frozen_string_literal: true

module Compliance
  module Approvals
    class IndexView < ApplicationComponent
      include UI::Theme

      def initialize(pending:, decided:, can_decide: false)
        @pending    = pending
        @decided    = decided
        @can_decide = can_decide
      end

      def view_template
        render Layout::Shell.new(
          active_nav:  :kyb_reviews,
          title:       "Approvals",
          breadcrumbs: [
            { label: "Compliance" },
            { label: "Approvals" }
          ]
        ) do
          div(style: "display:flex;flex-direction:column;gap:24px") do
            pending_section
            decided_section
          end
        end
      end

      private

      # ── Pending section ───────────────────────────────────────────────────────

      def pending_section
        render UI::Datatable.new(
          records:       @pending,
          empty_message: "No pending approvals. Adjustment proposals from Core appear here."
        ) do |t|
          t.header do
            div do
              p(style: TYPE_TITLE) { "Pending approvals" }
              p(style: "#{TYPE_CAPTION};margin-top:2px") do
                "Adjustments proposed by one officer that require sign-off from a second."
              end
            end
          end

          t.column("Break ID") do |r|
            code(style: TYPE_MONO) { r.core_break_id.to_s.first(12) + "…" }
          end

          t.column("Proposed by") do |r|
            div do
              p(style: TYPE_BODY_MD) { r.proposed_by }
              p(style: TYPE_CAPTION) { r.proposed_at.strftime("%d %b %Y, %H:%M") }
            end
          end

          t.column("Action") do |r|
            span(style: TYPE_BODY_MD) { r.action_summary }
          end

          t.column("Age") do |r|
            days = ((Time.current - r.proposed_at) / 86_400).round
            color = days > 2 ? "#dc2626" : "#d97706"
            span(style: "font-size:12px;font-weight:600;color:#{color}") do
              days == 0 ? "Today" : "#{days}d ago"
            end
          end

          if @can_decide
            t.actions do |r|
              form(action: compliance_approve_approval_path(r), method: "post",
                   data: { turbo_confirm: "Approve this adjustment? This cannot be undone." }) do
                input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
                button(type: "submit", class: DROPDOWN_ITEM) do
                  render UI::Icon.new(:check_circle, class: ICON_SM)
                  plain "Approve"
                end
              end
              div(class: DROPDOWN_SEP)
              button(type: "button", class: DROPDOWN_ITEM_DANGER,
                     data: { action: "click->dialog#open",
                             dialog_target_param: "reject-dialog-#{r.id}" }) do
                render UI::Icon.new(:x, class: ICON_SM)
                plain "Reject"
              end
              reject_dialog(r)
            end
          end
        end
      end

      # ── Decided section ───────────────────────────────────────────────────────

      def decided_section
        render UI::Datatable.new(
          records:       @decided,
          empty_message: "No decisions yet."
        ) do |t|
          t.header do
            p(style: TYPE_TITLE) { "Recent decisions" }
          end

          t.column("Break ID") do |r|
            code(style: TYPE_MONO) { r.core_break_id.to_s.first(12) + "…" }
          end

          t.column("State") do |r|
            render UI::StatusBadge.new(status: r.state)
          end

          t.column("Proposed by") do |r|
            span(style: TYPE_BODY_MD) { r.proposed_by }
          end

          t.column("Decided by") do |r|
            decided_by = r.approved_by.presence || "—"
            decided_at = r.approved_at || r.updated_at
            div do
              p(style: TYPE_BODY_MD) { decided_by }
              p(style: TYPE_CAPTION) { decided_at.strftime("%d %b %Y, %H:%M") }
            end
          end

          t.column("Proposed") do |r|
            span(style: TYPE_CAPTION) { r.proposed_at.strftime("%d %b %Y") }
          end
        end
      end

      # ── Reject dialog ─────────────────────────────────────────────────────────

      def reject_dialog(record)
        dialog(id: "reject-dialog-#{record.id}",
               style: "border:none;border-radius:16px;padding:0;box-shadow:0 20px 60px rgba(0,0,0,0.18);" \
                      "width:100%;max-width:440px;background:#fff") do
          div(style: "padding:22px 24px;border-bottom:1px solid #{BORDER}") do
            p(style: TYPE_TITLE) { "Reject adjustment" }
            p(style: "#{TYPE_CAPTION};margin-top:3px") do
              "Provide a reason for the rejection. This is recorded for the audit trail."
            end
          end
          form(action: compliance_reject_approval_path(record), method: "post",
               style: "padding:22px 24px;display:flex;flex-direction:column;gap:14px") do
            input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
            div do
              p(style: "#{TYPE_MICRO};margin-bottom:6px") { "Reason" }
              textarea(name: "reason", rows: 3, required: true,
                       placeholder: "Explain why this adjustment is being rejected…",
                       style: "width:100%;border:1px solid #{BORDER_MED};border-radius:10px;" \
                              "padding:9px 12px;font-size:13px;color:#{INK};background:#fff;" \
                              "outline:none;box-sizing:border-box;resize:vertical",
                       class: "placeholder:text-gray-400")
            end
            div(style: "display:flex;gap:10px;justify-content:flex-end") do
              button(type: "button", class: BTN_SECONDARY,
                     data: { action: "click->dialog#close",
                             dialog_target_param: "reject-dialog-#{record.id}" }) { "Cancel" }
              button(type: "submit", class: BTN_DANGER) do
                render UI::Icon.new(:x, class: ICON_SM)
                plain "Confirm rejection"
              end
            end
          end
        end
      end
    end
  end
end
