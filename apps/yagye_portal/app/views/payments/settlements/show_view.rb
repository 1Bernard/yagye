# frozen_string_literal: true

module Payments
  module Settlements
    class ShowView < ApplicationComponent
      include UI::Theme

      # Ordered happy-path lifecycle steps shown in the status tracker.
      # Branch states (awaiting_approval, dispatch_rejected, disputed, failed)
      # are spliced in dynamically based on the settlement's current state.
      MAIN_LIFECYCLE = %w[pending dispatched reconciling reconciled].freeze

      def initialize(settlement:, breaks: [], merchant: nil)
        @settlement = settlement
        @breaks     = breaks
        @merchant   = merchant
      end

      def view_template
        render Layout::Shell.new(
          active_nav: :settlements,
          title:      @settlement.period_label,
          breadcrumbs: [
            { label: "Settlements", href: settlements_path },
            { label: @settlement.period_label }
          ]
        ) do
          render UI::Grid.new(columns: :sidebar) do
            left_column
            right_column
          end
        end
      end

      private

      def left_column
        div(class: "flex flex-col gap-5") do
          hero_card
          financials_card
          breaks_card
        end
      end

      def right_column
        div(class: "flex flex-col gap-5") do
          status_card
          approval_card if @settlement.awaiting_approval?
          details_card
        end
      end

      # ── Hero ─────────────────────────────────────────────────────────────────

      def hero_card
        div(class: "#{SURFACE_CARD} px-8 py-7") do
          div(class: "flex items-start justify-between mb-6") do
            div do
              p(class: "#{TYPE_CAPTION} mb-[5px]") { plain "Settlement period" }
              p(class: "text-[22px] font-bold tracking-[-0.02em] leading-tight text-gray-900") do
                plain @settlement.period_label
              end
              p(class: "#{TYPE_CAPTION} mt-[5px]") do
                plain @settlement.provider_code&.humanize || "—"
                plain " · "
                plain (@settlement.mode || "live").capitalize
              end
            end
            render UI::StatusBadge.new(status: @settlement.state)
          end

          div(class: "grid grid-cols-3 gap-[1px] bg-gray-100 rounded-xl overflow-hidden") do
            meta_cell("Expected net", @settlement.formatted_expected_net, mono: true)
            meta_cell("Reported net", @settlement.formatted_reported_net, mono: true)
            meta_cell("Variance") do
              v     = @settlement.variance
              color = v.nil? ? MUTED_TEXT : (v.negative? ? RED : GREEN)
              p(class: "text-[13px] font-semibold tabular-nums", style: "color:#{color}") { plain variance_label }
            end
          end
        end
      end

      # ── Financial breakdown ───────────────────────────────────────────────────

      def financials_card
        render UI::Card.new do |c|
          c.header("Financial breakdown")
          c.body(padding: false) do
            section_label("Collections")
            render UI::DetailList.new do |list|
              list.row("Gross collected", @settlement.formatted_gross_amount)
              list.row("Platform fees",   @settlement.formatted_platform_fees)
              list.row("Expected net",    @settlement.formatted_expected_net)
            end

            section_label("Reconciliation", border: true)
            render UI::DetailList.new do |list|
              list.row("Reported net", @settlement.formatted_reported_net)
              list.row("Variance") do
                v     = @settlement.variance
                color = v.nil? ? MUTED_TEXT : (v.negative? ? RED : GREEN)
                span(class: "text-[13px] font-semibold tabular-nums", style: "color:#{color}") do
                  plain variance_label
                end
              end
            end

            section_label("Settlement info", border: true)
            render UI::DetailList.new do |list|
              list.row("Item count",  @settlement.item_count&.to_s || "—")
              list.row("Currency",    @settlement.currency)
              list.row("Value date",  fmt_date(@settlement.value_date))
            end
          end
        end
      end

      # ── Reconciliation breaks ─────────────────────────────────────────────────

      def breaks_card
        open_breaks = @breaks.reject { |b| %w[resolved written_off].include?(b["state"]) }

        render UI::Card.new do |c|
          c.header("Reconciliation breaks", icon: :alert_circle) do
            if open_breaks.any?
              span(class: "#{BADGE} #{STATUS_FAILED}") { plain open_breaks.size.to_s }
            end
          end
          c.body(padding: @breaks.empty?) do
            if @breaks.empty?
              div(class: "py-8 text-center") do
                p(class: TYPE_BODY_MD) { plain "No breaks detected" }
                p(class: "#{TYPE_CAPTION} mt-1") { plain "All records matched in this settlement period." }
              end
            else
              div(class: "divide-y divide-gray-50") do
                @breaks.each { |b| break_row(b) }
                if @breaks.size >= 10
                  div(class: "px-5 py-3 text-center") do
                    a(href: reconciliation_path,
                      class: "text-[12.5px] font-medium no-underline",
                      style: "color:#{BRAND}") do
                      plain "View all breaks →"
                    end
                  end
                end
              end
            end
          end
        end
      end

      def break_row(b)
        diff     = b["difference"].to_i
        currency = b["currency"] || "GHS"

        div(class: "flex items-center justify-between px-5 py-[11px]") do
          div do
            p(class: TYPE_BODY_MD) do
              plain (b["classification"] || "unknown").tr("_", " ").capitalize
            end
            p(class: "#{TYPE_CAPTION} mt-px") { plain b["id"].to_s.first(18) }
          end
          div(class: "flex items-center gap-3") do
            span(class: "text-[12.5px] font-semibold tabular-nums #{diff < 0 ? 'text-red-600' : 'text-green-600'}") do
              plain format_money_diff(diff, currency: currency)
            end
            render UI::StatusBadge.new(b["severity"].presence || "low")
          end
        end
      end

      # ── Settlement status tracker ─────────────────────────────────────────────

      def status_card
        steps = lifecycle_steps

        render UI::Card.new do |c|
          c.header("Settlement status")
          c.body do
            steps.each_with_index do |step, i|
              done = step == @settlement.state || lifecycle_past?(step, steps)
              state_step(step, done, last: i == steps.length - 1)
            end
          end
        end
      end

      def state_step(state, done, last: false)
        color = done ? GREEN : BORDER
        div(class: "flex gap-3") do
          div(class: "flex flex-col items-center flex-shrink-0") do
            div(class: "w-[10px] h-[10px] rounded-full flex-shrink-0 mt-[3px]", style: "background:#{color}")
            div(class: "w-[1px] flex-1 bg-gray-100 mt-1") unless last
          end
          div(class: last ? "" : "pb-4") do
            p(class: done ? TYPE_BODY_MD : TYPE_CAPTION) { plain state.humanize }
          end
        end
      end

      def lifecycle_steps
        case @settlement.state
        when "awaiting_approval"
          %w[pending awaiting_approval dispatched reconciling reconciled]
        when "dispatch_rejected"
          %w[pending awaiting_approval dispatch_rejected]
        when "disputed"
          %w[pending dispatched reconciled disputed]
        when "failed"
          MAIN_LIFECYCLE.take(last_completed_main_index + 1) + %w[failed]
        else
          MAIN_LIFECYCLE
        end
      end

      def lifecycle_past?(step, steps)
        current_idx = steps.index(@settlement.state).to_i
        step_idx    = steps.index(step).to_i
        step_idx < current_idx
      end

      def last_completed_main_index
        MAIN_LIFECYCLE.rindex { |s| s != @settlement.state && lifecycle_past?(s, MAIN_LIFECYCLE) } || 0
      end

      # ── Approval / rejection card ─────────────────────────────────────────────

      def approval_card
        render UI::Card.new do |c|
          c.header("Dispatch approval required")
          c.body do
            p(class: "#{TYPE_CAPTION} mb-5") do
              plain "This settlement batch exceeds the approval threshold and requires authorisation before the wire is sent."
            end

            if can?(:approve_dispatch?, @settlement)
              a(href: approve_dispatch_confirm_modal_settlement_path(@settlement.settlement_code),
                class: "#{BTN_SUCCESS} w-full justify-center mb-3",
                data: { turbo_frame: "modal-frame" }) do
                plain "Approve dispatch"
              end
            end

            if can?(:reject_dispatch?, @settlement)
              button(type: "button",
                     class: "w-full",
                     data: { action: "click->dialog#open",
                             dialog_target_param: "reject-dispatch-dialog" }) do
                render UI::Button.new(variant: :danger_outline, class: "w-full") { plain "Reject dispatch" }
              end
              reject_dispatch_dialog
            end
          end
        end
      end

      def reject_dispatch_dialog
        dialog(id: "reject-dispatch-dialog",
               class: "border-0 rounded-2xl p-0 shadow-2xl w-full max-w-[440px] bg-white") do
          div(class: "px-6 py-[22px] border-b border-gray-100") do
            p(class: TYPE_TITLE) { plain "Reject settlement dispatch" }
            p(class: "#{TYPE_CAPTION} mt-[3px]") { plain "Provide a reason. This is recorded for the audit trail." }
          end
          form(action: reject_dispatch_settlement_path(@settlement.settlement_code),
               method: "post",
               class: "px-6 py-[22px] flex flex-col gap-[14px]") do
            input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
            div do
              p(class: "#{TYPE_MICRO} mb-1.5") { plain "Reason" }
              textarea(name: "reason", rows: 3, required: true,
                       placeholder: "Explain why this dispatch is being rejected…",
                       class: "#{TEXTAREA_FIELD} placeholder:text-gray-400")
            end
            div(class: "flex gap-[10px] justify-end") do
              render UI::Button.new(variant: :secondary,
                     data: { action: "click->dialog#close",
                             dialog_target_param: "reject-dispatch-dialog" }) { plain "Cancel" }
              render UI::Button.new(variant: :danger, type: "submit") do
                plain "Confirm rejection"
              end
            end
          end
        end
      end

      # ── Details card ──────────────────────────────────────────────────────────

      def details_card
        render UI::Card.new do |c|
          c.header("Details")
          c.body(padding: false) do
            render UI::DetailList.new do |list|
              list.row("Settlement ID", stacked: true) { copyable_mono(@settlement.settlement_code) }
              list.row("Period") do
                div do
                  span(class: TYPE_BODY_MD) do
                    plain(@settlement.period_start ? fmt_datetime_utc(@settlement.period_start) : "—")
                  end
                  span(class: "block #{TYPE_CAPTION} mt-px") do
                    plain "to #{@settlement.period_end ? fmt_datetime_utc(@settlement.period_end) : '—'}"
                  end
                end
              end
              list.row("Merchant") do
                if @merchant
                  div do
                    span(class: "text-[13px] font-medium text-gray-800") do
                      plain @merchant.trading_name.presence || @settlement.merchant_code
                    end
                    span(class: "block #{TYPE_CAPTION} font-mono mt-px") { plain @settlement.merchant_code }
                  end
                else
                  span(class: TYPE_MONO) { plain @settlement.merchant_code || "—" }
                end
              end
              list.row("Rail") do
                div do
                  span(class: "#{TYPE_MONO} text-gray-800") { plain @settlement.provider_code || "—" }
                  span(class: "block #{TYPE_CAPTION} capitalize mt-px") { plain @settlement.mode || "—" }
                end
              end
              list.row("Dispatch ref", stacked: true) { copyable_mono(@settlement.bank_dispatch_ref || "Pending") }
              list.row("Dispatched at",
                @settlement.bank_dispatched_at ? fmt_datetime_utc(@settlement.bank_dispatched_at) : "Pending")
              list.row("Version",      @settlement.aggregate_version.to_s, mono: true)
              list.row("Last updated", fmt_datetime_utc(@settlement.last_applied_at))
            end
          end
        end
      end

      # ── Helpers ───────────────────────────────────────────────────────────────

      def variance_label
        v = @settlement.variance
        return "—" unless v

        format_money_diff(v, currency: @settlement.currency)
      end

      def section_label(text, border: false)
        border_class = border ? "border-t border-gray-50" : ""
        div(class: "px-6 pt-4 pb-1 #{border_class}") do
          p(class: TYPE_HEADING) { plain text }
        end
      end
    end
  end
end
