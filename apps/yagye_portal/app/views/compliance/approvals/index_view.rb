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
          render UI::PageHeader.new(
            title:    "Approvals",
            subtitle: "Adjustments proposed by one officer requiring sign-off from a second."
          )
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

          t.column("#", class: "text-gray-400 tabular-nums text-right w-8") { |_, i| plain((i + 1).to_s) }

          t.column("Break ID") do |r|
            code(class: TYPE_MONO) { plain r.core_break_id.to_s.first(12) + "…" }
          end

          t.column("Proposed by") do |r|
            div do
              p(class: TYPE_BODY_MD) { plain r.proposed_by }
              p(class: TYPE_CAPTION) { plain r.proposed_at.strftime("%d %b %Y, %H:%M") }
            end
          end

          t.column("Proposed adjustment") do |r|
            action  = r.proposed_action
            type    = (action["type"] || action["action"] || "adjustment").to_s.downcase
            note    = action["note"].presence
            amount  = action["amount"]
            badge_class = case type
                          when "credit", "reversal"  then "bg-green-50 text-green-700"
                          when "debit", "chargeback" then "bg-red-50 text-red-700"
                          when "fee"                 then "bg-amber-50 text-amber-700"
                          else                            "bg-gray-100 text-gray-600"
                          end
            div(class: "flex flex-col gap-1") do
              div(class: "flex items-center gap-2") do
                span(class: "#{badge_class} inline-flex items-center rounded px-1.5 py-0.5 text-[10.5px] font-semibold uppercase tracking-wide") do
                  plain type.humanize
                end
                if amount.present?
                  whole, frac = amount.to_i.divmod(100)
                  span(class: "#{TYPE_MONO} text-[12px]") { plain "GHS #{sprintf('%d.%02d', whole, frac)}" }
                end
              end
              p(class: "#{TYPE_CAPTION} leading-snug") { plain note } if note
            end
          end

          t.column("Age") do |r|
            days  = ((Time.current - r.proposed_at) / 86_400).round
            label = days.zero? ? "Today" : "#{days}d ago"
            css   = days > 7 ? "text-red-600 font-semibold" : days > 2 ? "text-amber-600 font-semibold" : "text-gray-500"
            span(class: "text-[12px] #{css}") { plain label }
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

          t.column("#", class: "text-gray-400 tabular-nums text-right w-8") { |_, i| plain((i + 1).to_s) }

          t.column("Break ID") do |r|
            code(class: TYPE_MONO) { plain r.core_break_id.to_s.first(12) + "…" }
          end

          t.column("Decision") do |r|
            div(class: "flex flex-col gap-1") do
              render UI::StatusBadge.new(status: r.state)
              if r.rejected? && r.rejected_reason.present?
                p(class: "#{TYPE_CAPTION} italic max-w-[200px] leading-tight") { plain r.rejected_reason.truncate(80) }
              end
            end
          end

          t.column("Proposed by") do |r|
            span(class: TYPE_BODY_MD) { plain r.proposed_by }
          end

          t.column("Decided by") do |r|
            decided_by = r.approved_by.presence || "—"
            decided_at = r.approved_at
            div do
              p(class: TYPE_BODY_MD) { plain decided_by }
              p(class: TYPE_CAPTION) { plain decided_at.strftime("%d %b %Y, %H:%M") } if decided_at
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
