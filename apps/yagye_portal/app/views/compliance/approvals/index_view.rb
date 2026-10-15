# frozen_string_literal: true

module Compliance
  module Approvals
    class IndexView < ApplicationComponent
      include UI::Theme

      def initialize(tab:, records:, pagy:, pending_count:, can_decide: false, current_user_code: nil)
        @tab               = tab
        @records           = records
        @pagy              = pagy
        @pending_count     = pending_count
        @can_decide        = can_decide
        @current_user_code = current_user_code
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
          tab_bar
          @tab == "decided" ? decided_section : pending_section
        end
      end

      private

      def tab_bar
        render UI::Tabs.new do |t|
          t.tab "Pending",
                href:   compliance_approvals_path(tab: "pending"),
                active: @tab == "pending",
                count:  @pending_count > 0 ? @pending_count : nil
          t.tab "Decided",
                href:   compliance_approvals_path(tab: "decided"),
                active: @tab == "decided"
        end
      end

      # ── Pending tab ───────────────────────────────────────────────────────────

      def pending_section
        render UI::Datatable.new(
          records:       @records,
          pagy:          @pagy,
          empty_message: "No pending approvals. Adjustment proposals from Core appear here."
        ) do |t|
          t.column("#", class: "text-gray-400 tabular-nums text-right w-8") { |_, i| plain((i + 1).to_s) }

          t.column("Break ID") do |r|
            code(class: TYPE_MONO) { plain r.core_break_id.to_s.first(12) + "…" }
          end

          t.column("Proposed by") do |r|
            div do
              p(class: TYPE_BODY_MD) do
                plain r.proposed_by
                if r.proposed_by == @current_user_code
                  span(class: "#{BADGE} #{STATUS_WARNING} ml-2") { plain "You" }
                end
              end
              p(class: TYPE_CAPTION) { plain fmt_datetime(r.proposed_at) }
            end
          end

          t.column("Proposed adjustment") do |r|
            action  = r.proposed_action
            type    = (action["type"] || action["action"] || "adjustment").to_s.downcase
            note    = action["note"].presence
            amount  = action["amount"]
            badge_class = case type
            when "credit", "reversal"  then STATUS_SUCCESS
            when "debit", "chargeback" then STATUS_FAILED
            when "fee"                 then STATUS_WARNING
            else                            STATUS_NEUTRAL
            end
            div(class: "flex flex-col gap-1") do
              div(class: "flex items-center gap-2") do
                span(class: "#{badge_class} #{BADGE} uppercase tracking-wide") { plain type.humanize }
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
              own = r.proposed_by == @current_user_code
              if own
                div(class: "#{DROPDOWN_ITEM} opacity-40 cursor-not-allowed select-none") do
                  render UI::Icon.new(:shield, class: ICON_SM)
                  plain "Awaiting another officer"
                end
              else
                a(href: approve_modal_compliance_approval_path(r),
                  class: DROPDOWN_ITEM,
                  data: { turbo_frame: "modal-frame" }) do
                  render UI::Icon.new(:check_circle, class: ICON_SM)
                  plain "Approve"
                end
                div(class: DROPDOWN_SEP)
                a(href: reject_modal_compliance_approval_path(r),
                  class: DROPDOWN_ITEM_DANGER,
                  data: { turbo_frame: "modal-frame" }) do
                  render UI::Icon.new(:x, class: ICON_SM)
                  plain "Reject"
                end
              end
            end
          end
        end
      end

      # ── Decided tab ───────────────────────────────────────────────────────────

      def decided_section
        render UI::Datatable.new(
          records:       @records,
          pagy:          @pagy,
          empty_message: "No decisions yet."
        ) do |t|
          t.column("#", class: "text-gray-400 tabular-nums text-right w-8") { |_, i| plain((i + 1).to_s) }

          t.column("Break ID") do |r|
            code(class: TYPE_MONO) { plain r.core_break_id.to_s.first(12) + "…" }
          end

          t.column("Decision") do |r|
            div(class: "flex flex-col gap-1") do
              render UI::StatusBadge.new(status: r.state)
              if r.rejected? && r.rejected_reason.present?
                p(class: "#{TYPE_CAPTION} italic max-w-[200px] leading-tight") do
                  plain r.rejected_reason.truncate(80)
                end
              end
            end
          end

          t.column("Proposed by") do |r|
            span(class: TYPE_BODY_MD) { plain r.proposed_by }
          end

          t.column("Decided by") do |r|
            decided_by = r.approved_by.presence || r.rejected_by.presence || "—"
            decided_at = r.approved_at || r.rejected_at
            div do
              p(class: TYPE_BODY_MD) { plain decided_by }
              p(class: TYPE_CAPTION) { plain fmt_datetime(decided_at) } if decided_at
            end
          end

          t.column("Proposed") do |r|
            span(class: TYPE_CAPTION) { plain fmt_date(r.proposed_at) }
          end
        end
      end
    end
  end
end
