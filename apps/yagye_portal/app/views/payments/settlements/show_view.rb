# frozen_string_literal: true

module Payments
  module Settlements
    class ShowView < ApplicationComponent
      include UI::Theme

      BREAK_SEVERITY_COLORS = {
        "critical" => "text-red-700 bg-red-50",
        "high"     => "text-amber-700 bg-amber-50",
        "medium"   => "text-blue-700 bg-blue-50",
        "low"      => "text-gray-600 bg-gray-100"
      }.freeze

      def initialize(settlement:, breaks: [])
        @settlement = settlement
        @breaks     = breaks
      end

      def view_template
        render Layout::Shell.new(
          active_nav: :settlements,
          title:      @settlement.period_label,
          breadcrumbs: [
            { label: "Settlements", url: settlements_path },
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
          state_card
          approval_card if @settlement.awaiting_approval?
          details_card
        end
      end

      def hero_card
        div(class: "bg-white border border-gray-100 rounded-2xl px-8 py-7") do
          div(class: "flex items-start justify-between mb-5") do
            div do
              p(class: "#{TYPE_CAPTION} mb-1") { plain "Settlement period" }
              p(class: "text-[22px] font-bold text-gray-900") { plain @settlement.period_label }
            end
            render UI::StatusBadge.new(status: @settlement.state)
          end
          div(class: "grid grid-cols-3 gap-[1px] bg-gray-100 rounded-xl overflow-hidden") do
            meta_cell("Expected net", @settlement.formatted_expected_net)
            meta_cell("Reported net", @settlement.formatted_reported_net)
            meta_cell("Variance",     variance_label)
          end
        end
      end

      def financials_card
        render UI::Card.new do |c|
          c.header("Financial breakdown")
          c.body(padding: false) do
            render UI::DetailList.new do |list|
              list.row("Expected net",  @settlement.formatted_expected_net)
              list.row("Reported net",  @settlement.formatted_reported_net)
              list.row("Variance") do
                v     = @settlement.variance
                color = v.nil? ? MUTED_TEXT : (v.negative? ? "#dc2626" : "#16a34a")
                span(class: "text-[13px] font-semibold", style: "color:#{color}") { plain variance_label }
              end
              list.row("Item count",   @settlement.item_count&.to_s || "—")
              list.row("Currency",     @settlement.currency)
              list.row("Value date",   @settlement.value_date&.strftime("%d %b %Y") || "—")
            end
          end
        end
      end

      def breaks_card
        open_breaks = @breaks.reject { |b| %w[resolved written_off].include?(b["state"]) }

        render UI::Card.new do |c|
          c.header("Reconciliation breaks", icon: :alert_circle) do
            if open_breaks.any?
              span(class: "inline-flex items-center px-2 py-0.5 rounded-full text-[11px] font-semibold bg-red-50 text-red-700") do
                plain open_breaks.size.to_s
              end
            end
          end
          c.body(padding: @breaks.empty?) do
            if @breaks.empty?
              div(class: "py-8 text-center") do
                p(class: TYPE_BODY_MD) { plain "No breaks detected" }
                p(class: TYPE_CAPTION) { plain "All records matched in this settlement period." }
              end
            else
              div(class: "divide-y divide-gray-50") do
                @breaks.each do |b|
                  break_row(b)
                end
                if @breaks.size >= 10
                  div(class: "px-5 py-3 text-center") do
                    a(href: reconciliation_path, class: "text-[12.5px] font-medium text-[#{BRAND}] no-underline") do
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
        severity_cls = BREAK_SEVERITY_COLORS[b["severity"]] || "text-gray-500 bg-gray-100"
        diff     = b["difference"].to_i
        currency = b["currency"] || "GHS"

        div(class: "flex items-center justify-between px-5 py-3") do
          div do
            p(class: TYPE_BODY_MD) do
              plain (b["classification"] || "unknown").tr("_", " ").capitalize
            end
            p(class: TYPE_CAPTION) { plain b["id"].to_s.first(18) }
          end
          div(class: "flex items-center gap-3") do
            span(class: "text-[12.5px] font-semibold #{diff < 0 ? 'text-red-600' : 'text-green-600'} tabular-nums") do
              plain format_money_diff(diff, currency: currency)
            end
            span(class: "inline-flex items-center px-2 py-0.5 rounded-full text-[10.5px] font-semibold #{severity_cls}") do
              plain (b["severity"] || "—").capitalize
            end
          end
        end
      end

      def state_card
        render UI::Card.new do |c|
          c.header("Reconciliation state")
          c.body do
            PortalSettlement::STATES.each_with_index do |s, i|
              state_step(s, @settlement.state == s || past_state?(s), last: i == PortalSettlement::STATES.length - 1)
            end
          end
        end
      end

      def state_step(state, done, last: false)
        color = done ? "#16a34a" : BORDER
        div(class: "flex gap-3") do
          div(class: "flex flex-col items-center flex-shrink-0") do
            div(class: "w-[10px] h-[10px] rounded-full flex-shrink-0 mt-[3px]", style: "background:#{color}")
            div(class: "w-[1px] flex-1 bg-gray-100 mt-1") unless last
          end
          div(class: last ? "" : "pb-[14px]") do
            p(class: (done ? TYPE_BODY_MD : TYPE_CAPTION)) { plain state.humanize }
          end
        end
      end

      def approval_card
        render UI::Card.new do |c|
          c.header("Dispatch approval required")
          c.body do
            p(class: "#{TYPE_CAPTION} mb-5") do
              plain "This settlement batch exceeds the approval threshold and requires authorisation before the wire is sent."
            end

            if can?(:approve_dispatch?, @settlement)
              form(action: approve_dispatch_settlement_path(@settlement.settlement_code),
                   method: "post",
                   class: "mb-3",
                   data: { turbo_confirm: "Approve this dispatch? The wire will be sent immediately." }) do
                input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
                render UI::Button.new(variant: :primary, type: "submit", class: "w-full") do
                  plain "Approve dispatch"
                end
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
            p(class: "#{TYPE_CAPTION} mt-[3px]") do
              plain "Provide a reason. This is recorded for the audit trail."
            end
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

      def details_card
        render UI::Card.new do |c|
          c.header("Details")
          c.body(padding: false) do
            render UI::DetailList.new do |list|
              list.row("Settlement code",  @settlement.settlement_code, mono: true)
              list.row("Merchant code",    @settlement.merchant_code || "—", mono: true)
              list.row("Provider code",    @settlement.provider_code || "—", mono: true)
              list.row("Mode",             @settlement.mode&.capitalize || "—")
              list.row("Dispatch ref",     @settlement.bank_dispatch_ref || "—", mono: true)
              list.row("Dispatched at",    @settlement.bank_dispatched_at&.strftime("%d %b %Y at %H:%M UTC") || "Pending")
              list.row("Version",          @settlement.aggregate_version.to_s, mono: true)
              list.row("Last updated",     @settlement.last_applied_at&.strftime("%d %b %Y at %H:%M UTC") || "—")
            end
          end
        end
      end

      def variance_label
        v = @settlement.variance
        return "—" unless v

        format_money_diff(v, currency: @settlement.currency)
      end

      def past_state?(state)
        order   = PortalSettlement::STATES
        current = @settlement.state
        order.index(state).to_i < order.index(current).to_i
      end
    end
  end
end
