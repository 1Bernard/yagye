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
          active_nav:  :approvals,
          title:       "Approvals",
          breadcrumbs: [
            { label: "Compliance" },
            { label: "Approvals" }
          ]
        ) do
          div(class: "flex flex-col gap-6") do
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
              p(class: TYPE_TITLE) { plain "Pending approvals" }
              p(class: "#{TYPE_CAPTION} mt-0.5") do
                plain "Adjustments proposed by one officer that require sign-off from a second."
              end
            end
          end

          t.column("Break ID") do |r|
            code(class: TYPE_MONO) { plain r.core_break_id.to_s.first(12) + "…" }
          end

          t.column("Proposed by") do |r|
            div do
              p(class: TYPE_BODY_MD) { plain r.proposed_by }
              p(class: TYPE_CAPTION) { plain r.proposed_at.strftime("%d %b %Y, %H:%M") }
            end
          end

          t.column("Action") do |r|
            span(class: TYPE_BODY_MD) { plain r.action_summary }
          end

          t.column("Age") do |r|
            days = ((Time.current - r.proposed_at) / 86_400).round
            color = days > 2 ? "#dc2626" : "#d97706"
            span(class: "text-[12px] font-semibold", style: "color:#{color}") do
              plain days == 0 ? "Today" : "#{days}d ago"
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
            end
          end
        end

        # Dialogs must be outside the datatable (actions block runs in Datatable context via
        # instance_exec, so IndexView methods are not in scope there).
        @pending.each { |r| reject_dialog(r) } if @can_decide
      end

      # ── Decided section ───────────────────────────────────────────────────────

      def decided_section
        render UI::Datatable.new(
          records:       @decided,
          empty_message: "No decisions yet."
        ) do |t|
          t.header do
            p(class: TYPE_TITLE) { plain "Recent decisions" }
          end

          t.column("Break ID") do |r|
            code(class: TYPE_MONO) { plain r.core_break_id.to_s.first(12) + "…" }
          end

          t.column("State") do |r|
            render UI::StatusBadge.new(status: r.state)
          end

          t.column("Proposed by") do |r|
            span(class: TYPE_BODY_MD) { plain r.proposed_by }
          end

          t.column("Decided by") do |r|
            decided_by = r.approved_by.presence || "—"
            decided_at = r.approved_at || r.updated_at
            div do
              p(class: TYPE_BODY_MD) { plain decided_by }
              p(class: TYPE_CAPTION) { plain decided_at.strftime("%d %b %Y, %H:%M") }
            end
          end

          t.column("Proposed") do |r|
            span(class: TYPE_CAPTION) { plain r.proposed_at.strftime("%d %b %Y") }
          end
        end
      end

      # ── Reject dialog ─────────────────────────────────────────────────────────

      def reject_dialog(record)
        dialog(id: "reject-dialog-#{record.id}",
               class: "border-0 rounded-2xl p-0 shadow-2xl w-full max-w-[440px] bg-white") do
          div(class: "px-6 py-[22px] border-b border-gray-100") do
            p(class: TYPE_TITLE) { plain "Reject adjustment" }
            p(class: "#{TYPE_CAPTION} mt-[3px]") do
              plain "Provide a reason for the rejection. This is recorded for the audit trail."
            end
          end
          form(action: compliance_reject_approval_path(record), method: "post",
               class: "px-6 py-[22px] flex flex-col gap-[14px]") do
            input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
            div do
              p(class: "#{TYPE_MICRO} mb-1.5") { plain "Reason" }
              textarea(name: "reason", rows: 3, required: true,
                       placeholder: "Explain why this adjustment is being rejected…",
                       class: "#{TEXTAREA_FIELD} placeholder:text-gray-400")
            end
            div(class: "flex gap-[10px] justify-end") do
              render UI::Button.new(variant: :secondary,
                     data: { action: "click->dialog#close",
                             dialog_target_param: "reject-dialog-#{record.id}" }) { plain "Cancel" }
              render UI::Button.new(variant: :danger, type: "submit") do
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
