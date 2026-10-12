# frozen_string_literal: true

module Payments
  module Reconciliation
    class IndexView < ApplicationComponent
      include UI::Theme

      CLASSIFICATION_LABELS = {
        "missing_on_right"    => "Missing on PSP",
        "missing_on_left"     => "Missing on ledger",
        "amount_mismatch"     => "Amount mismatch",
        "duplicate_on_left"   => "Duplicate on ledger",
        "duplicate_on_right"  => "Duplicate on PSP",
        "timing_difference"   => "Timing difference",
        "fee_discrepancy"     => "Fee discrepancy",
        "currency_mismatch"   => "Currency mismatch",
        "unknown"             => "Unknown"
      }.freeze

      def initialize(breaks:, query: nil, state_filter: nil, severity_filter: nil, from: nil, to: nil)
        @breaks          = breaks
        @query           = query
        @state_filter    = state_filter
        @severity_filter = severity_filter
        @from            = from
        @to              = to
      end

      def view_template
        render Layout::Shell.new(
          active_nav:  :reconciliation,
          title:       "Reconciliation",
          breadcrumbs: [ { label: "Reconciliation" } ]
        ) do
          render UI::PageHeader.new(
            title:    "Reconciliation breaks",
            subtitle: "Discrepancies between Yagye ledger records and PSP settlement reports."
          )
          stat_band
          breaks_table
        end
      end

      private

      def stat_band
        open      = @breaks.reject { |b| %w[resolved written_off].include?(b["state"]) }
        critical  = @breaks.select { |b| b["severity"] == "critical" && b["state"] != "resolved" }
        overdue   = @breaks.select { |b| sla_overdue?(b) }
        resolved  = @breaks.select { |b| b["state"] == "resolved" }

        render UI::Grid.new(columns: 4) do
          stat_cell("Open breaks",    open.size.to_s,     icon: :alert_circle,  color: RED,    tint: TINT_RED)
          stat_cell("Critical",       critical.size.to_s, icon: :alert_circle,  color: RED,    tint: TINT_RED)
          stat_cell("SLA overdue",    overdue.size.to_s,  icon: :clock,         color: AMBER,  tint: TINT_AMBER)
          stat_cell("Resolved",       resolved.size.to_s, icon: :check_circle,  color: GREEN,  tint: TINT_GREEN)
        end
      end

      def breaks_table
        render UI::Datatable.new(records: @breaks,
                                 empty_message: "No reconciliation breaks detected.") do |t|
          t.header { toolbar_content }

          t.column("#", class: "text-gray-400 tabular-nums text-right w-8") do |_, i|
            plain((i + 1).to_s)
          end

          t.column("Break ID") do |b|
            code(class: TYPE_MONO) { plain b["id"].to_s.first(16) }
          end

          t.column("Classification") do |b|
            label = CLASSIFICATION_LABELS[b["classification"]] || b["classification"]&.humanize || "—"
            span(class: TYPE_BODY_MD) { plain label }
          end

          t.column("Severity") do |b|
            render UI::StatusBadge.new(b["severity"].presence || "low")
          end

          t.column("Difference", class: "text-right tabular-nums") do |b|
            diff = b["difference"].to_i
            color = diff < 0 ? "text-red-600" : "text-green-600"
            currency = b["currency"] || "GHS"
            span(class: "text-[13px] font-semibold #{color}") do
              plain format_money_diff(diff, currency: currency)
            end
          end

          t.column("Status") do |b|
            render UI::StatusBadge.new(b["state"].presence || "detected")
          end

          t.column("SLA") do |b|
            if b["sla_due_at"].present? && b["state"] != "resolved"
              due = Time.parse(b["sla_due_at"]) rescue nil
              if due
                days = (due.to_date - Date.current).to_i
                if days < 0
                  cls, label = STATUS_FAILED, "Overdue"
                else
                  date_str  = due.strftime("%-d %b")
                  countdown = days == 0 ? "today" : days == 1 ? "tomorrow" : "#{days}d left"
                  label     = "#{date_str} · #{countdown}"
                  cls       = days <= 2 ? STATUS_FAILED : days <= 6 ? STATUS_WARNING : STATUS_SUCCESS
                end
                span(class: "#{cls} #{BADGE} whitespace-nowrap") { plain label }
              else
                span(class: "text-[11px] text-gray-400") { plain "—" }
              end
            else
              span(class: "text-[11px] text-gray-400") { plain "—" }
            end
          end

          t.column("Detected") do |b|
            plain fmt_date(b["detected_at"] ? Time.parse(b["detected_at"]) : nil)
          end

          t.actions do |b|
            a(href: reconciliation_break_path(b["id"]), class: DROPDOWN_ITEM) do
              render UI::Icon.new(:eye, class: ICON_SM)
              plain "View"
            end
          end
        end
      end

      # ── Toolbar ─────────────────────────────────────────────────────────────

      def toolbar_content
        filter_count = [ @state_filter.present?, @severity_filter.present?,
                         @from.present?, @to.present? ].count(true)

        form(action: reconciliation_path, method: "get",
             data: { controller: "filter-form", filter_form_target: "form" }) do
          div(class: FILTER_SEARCH_WRAP) do
            span(class: "flex w-[13px] h-[13px] text-gray-400 flex-shrink-0") do
              render UI::Icon.new(:search, class: "w-full h-full")
            end
            input(type: "search", name: "q", value: @query,
                  placeholder: "Search break ID or classification…",
                  class: FILTER_SEARCH_INPUT)
          end
        end

        div(class: "flex items-center gap-2") do
          filter_btn(filter_count)
        end
      end

      def filter_btn(filter_count)
        a(href: filter_reconciliation_path(q: @query, state: @state_filter, severity: @severity_filter,
                                           from: @from, to: @to),
          class: "inline-flex items-center gap-[5px] px-3 h-8 border rounded-[9px] " \
                 "text-[12.5px] font-medium bg-white cursor-pointer transition-colors no-underline " \
                 "#{filter_count > 0 ? 'border-gray-400 text-gray-900' : 'border-gray-200 text-gray-600'} " \
                 "hover:border-gray-400",
          data: { turbo_frame: "drawer-frame" }) do
          render UI::Icon.new(:filter, class: "w-3 h-3")
          plain "Filters"
          if filter_count > 0
            span(class: "ml-[2px] inline-flex items-center justify-center w-4 h-4 rounded-full " \
                        "bg-[#3D47F5] text-white text-[9px] font-bold leading-none") do
              plain filter_count.to_s
            end
          end
        end
      end

      def sla_overdue?(b)
        return false unless b["sla_due_at"].present? && b["state"] != "resolved"
        Time.parse(b["sla_due_at"]) < Time.current
      rescue
        false
      end
    end
  end
end
