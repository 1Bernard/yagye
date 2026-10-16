# frozen_string_literal: true

module Ops
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
            subtitle: "Imported bank statement files for reconciliation."
          ) do
            a(href: new_ops_bank_statement_path,
              class: "#{BTN_PRIMARY} no-underline") do
              plain "Import statement"
            end
          end

          account_filter_form
          statements_table
        end
      end

      private

      def account_filter_form
        form(action: ops_bank_statements_path, method: "get", class: "mb-4") do
          div(class: FILTER_SEARCH_WRAP) do
            span(class: "flex w-[13px] h-[13px] text-gray-400 flex-shrink-0") do
              render UI::Icon.new(:search, class: "w-full h-full")
            end
            input(type: "search", name: "account_reference", value: @account_reference,
                  placeholder: "Filter by account reference…",
                  class: FILTER_SEARCH_INPUT)
          end
        end
      end

      def statements_table
        render UI::Datatable.new(records: @statements,
                                 empty_message: "No bank statements imported yet.") do |t|
          t.column("Account reference") do |s|
            code(class: TYPE_MONO) { plain s["account_reference"].to_s }
          end

          t.column("Statement date") do |s|
            plain s["statement_date"].to_s
          end

          t.column("Lines", class: "text-right tabular-nums") do |s|
            plain (s["line_count"] || s["lines"]&.size || "—").to_s
          end

          t.column("Imported") do |s|
            plain fmt_datetime(s["inserted_at"] ? Time.parse(s["inserted_at"]) : nil)
          end

          t.actions do |s|
            a(href: ops_bank_statement_path(s["id"]), class: DROPDOWN_ITEM) do
              render UI::Icon.new(:eye, class: ICON_SM)
              plain "View"
            end
          end
        end
      end
    end
  end
end
