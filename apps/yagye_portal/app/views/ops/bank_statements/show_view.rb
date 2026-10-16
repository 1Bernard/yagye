# frozen_string_literal: true

module Ops
  module BankStatements
    class ShowView < ApplicationComponent
      include UI::Theme

      MATCH_LABELS = {
        "matched"    => "Matched",
        "unmatched"  => "Unmatched",
        "duplicate"  => "Duplicate",
        "ignored"    => "Ignored"
      }.freeze

      def initialize(statement:)
        @statement = statement
      end

      def view_template
        stmt_id  = @statement["id"].to_s
        acct_ref = @statement["account_reference"].to_s

        render Layout::Shell.new(
          active_nav:  :reconciliation,
          title:       "Statement #{acct_ref}",
          breadcrumbs: [
            { label: "Bank Statements", href: ops_bank_statements_path },
            { label: acct_ref }
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
          lines_card
        end
      end

      def right_column
        div(class: "flex flex-col gap-4") do
          meta_card
        end
      end

      def meta_card
        render UI::Card.new do |c|
          c.header("Details")
          c.body(padding: false) do
            render UI::DetailList.new do |list|
              list.row("Account reference") do
                code(class: TYPE_MONO) { plain @statement["account_reference"].to_s }
              end
              list.row("Statement date",  @statement["statement_date"].to_s)
              list.row("Imported",        fmt_datetime(parse_time(@statement["inserted_at"])))
              list.row("Lines",           (@statement["lines"]&.size || 0).to_s)
            end
          end
        end
      end

      def lines_card
        lines = Array(@statement["lines"])
        render UI::Card.new do |c|
          c.header("Statement lines", icon: :list)
          c.body(padding: false) do
            if lines.empty?
              div(class: "py-8 text-center") do
                p(class: TYPE_CAPTION) { plain "No lines in this statement." }
              end
            else
              render UI::Datatable.new(records: lines, empty_message: "No lines.") do |t|
                t.column("Date") do |l|
                  plain l["date"].to_s
                end
                t.column("Description") do |l|
                  span(class: "text-[13px] text-gray-700 truncate max-w-xs block") do
                    plain l["description"].to_s
                  end
                end
                t.column("Amount", class: "text-right tabular-nums") do |l|
                  amount = l["amount"].to_i
                  color  = amount < 0 ? "text-red-600" : "text-gray-900"
                  span(class: "text-[13px] font-medium #{color}") do
                    plain format("GHS %.2f", amount / 100.0)
                  end
                end
                t.column("Match state") do |l|
                  state = l["match_state"].to_s.presence || "unmatched"
                  label = MATCH_LABELS[state] || state.humanize
                  render UI::StatusBadge.new(state, label: label)
                end
              end
            end
          end
        end
      end

      def parse_time(val)
        return nil if val.blank?
        Time.parse(val)
      rescue
        nil
      end
    end
  end
end
