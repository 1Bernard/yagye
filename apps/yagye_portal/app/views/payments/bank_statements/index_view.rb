# frozen_string_literal: true

module Payments
  module BankStatements
    class IndexView < ApplicationComponent
      include UI::Theme

      def initialize(statements:, account_reference: nil)
        @statements        = statements
        @account_reference = account_reference
      end

      def view_template
        render Layout::Shell.new(
          active_nav:  :bank_statements,
          title:       "Bank Statements",
          breadcrumbs: [ { label: "Bank Statements" } ]
        ) do
          render UI::PageHeader.new(
            title:    "Bank Statements",
            subtitle: "Imported statement files for bank reconciliation."
          ) do
            render UI::Button.new(variant: :primary,
                                 href: upload_modal_payments_bank_statement_path,
                                 data: { turbo_frame: "modal-frame" }) do
              render UI::Icon.new(:upload, class: ICON_SM)
              plain "Import statement"
            end
          end

          stat_band
          statements_table
        end
      end

      private

      def stat_band
        total   = @statements.size
        lines   = @statements.sum { |s| (s["line_count"] || s["lines"]&.size).to_i }
        accounts = @statements.map { |s| s["account_reference"] }.compact.uniq.size
        recent  = @statements.count do |s|
          next false if s["ingested_at"].blank?
          Time.parse(s["ingested_at"]) >= 30.days.ago
        rescue ArgumentError, TypeError
          false
        end

        render UI::Grid.new(columns: 4) do
          stat_cell("Statements",       total.to_s,    icon: :file,         color: BRAND,  tint: TINT_BRAND)
          stat_cell("Total lines",      lines.to_s,    icon: :list,         color: BRAND,  tint: TINT_BRAND)
          stat_cell("Accounts tracked", accounts.to_s, icon: :layers,       color: AMBER,  tint: TINT_AMBER)
          stat_cell("Last 30 days",     recent.to_s,   icon: :calendar,     color: GREEN,  tint: TINT_GREEN)
        end
      end

      def statements_table
        render UI::Datatable.new(records: @statements,
                                 empty_message: "No bank statements imported yet.") do |t|
          t.header { toolbar }

          t.column("Account") do |s|
            code(class: TYPE_MONO) { plain s["account_reference"].to_s }
          end

          t.column("Statement date") do |s|
            plain s["statement_date"].to_s
          end

          t.column("Lines", class: "text-right tabular-nums") do |s|
            plain (s["line_count"] || s["lines"]&.size || "—").to_s
          end

          t.column("Imported") do |s|
            plain fmt_datetime(s["ingested_at"] ? Time.parse(s["ingested_at"]) : nil)
          end

          t.actions do |s|
            a(href: payments_bank_statement_path(s["id"]), class: DROPDOWN_ITEM) do
              render UI::Icon.new(:eye, class: ICON_SM)
              plain "View"
            end
          end
        end
      end

      def toolbar
        account_ref = @account_reference

        form(action: payments_bank_statements_path, method: "get",
             data: { controller: "filter-form", filter_form_target: "form" }) do
          div(class: FILTER_SEARCH_WRAP) do
            span(class: "flex w-[13px] h-[13px] text-gray-400 flex-shrink-0") do
              render UI::Icon.new(:search, class: "w-full h-full")
            end
            input(type: "search", name: "account_reference", value: account_ref,
                  placeholder: "Filter by account reference…",
                  class: FILTER_SEARCH_INPUT)
          end
        end
      end
    end
  end
end
