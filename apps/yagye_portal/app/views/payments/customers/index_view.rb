# frozen_string_literal: true

module Payments
  module Customers
    class IndexView < ApplicationComponent
      include UI::Theme

      def initialize(customers:, query: nil)
        @customers = customers
        @query     = query
      end

      def view_template
        render Layout::Shell.new(
          active_nav: :customers,
          title:      "Customers",
          subtitle:   "All customers who have transacted through your account"
        ) do
          render UI::PageHeader.new(
            title:    "Customers",
            subtitle: "Customers are created automatically when a payment is initiated."
          )

          customers_table
        end
      end

      private

      def customers_table
        render UI::Datatable.new(
          records:       @customers,
          pagy:          nil,
          empty_message: empty_msg
        ) do |t|
          t.header { toolbar }

          t.column("#", class: "text-gray-400 tabular-nums text-right w-8") { |_, i| plain((i + 1).to_s) }

          t.column("Reference", class: "font-mono text-[11.5px]") do |c|
            plain(c["merchant_customer_ref"] || c["id"]&.first(12) || "—")
          end

          t.column("KYC Tier") do |c|
            tier = c["kyc_tier"].to_i
            css  = case tier
                   when 2    then "bg-green-50 text-green-700"
                   when 1    then "bg-amber-50 text-amber-700"
                   else           "bg-gray-100 text-gray-500"
                   end
            span(class: "inline-flex items-center px-2 py-0.5 rounded-full text-[11px] font-medium #{css}") do
              plain "Tier #{tier}"
            end
          end

          t.column("MSISDN", class: "font-mono text-[11.5px]") do |c|
            plain(c["msisdn"] || "—")
          end

          t.column("Created") do |c|
            ts = c["inserted_at"] || c["created_at"]
            plain(ts ? Time.parse(ts).strftime("%d %b %Y") : "—")
          end

          t.actions do |c|
            a(href: customer_path(c["id"]), class: DROPDOWN_ITEM) do
              render UI::Icon.new(:eye, class: ICON_SM)
              plain "View"
            end
          end
        end
      end

      def toolbar
        form(action: customers_path, method: "get") do
          div(class: FILTER_SEARCH_WRAP) do
            span(class: "flex w-[13px] h-[13px] text-gray-400 flex-shrink-0") do
              render UI::Icon.new(:search, class: "w-full h-full")
            end
            input(type: "search", name: "q", value: @query,
                  placeholder: "Search by reference or customer ID…",
                  class: FILTER_SEARCH_INPUT)
          end
        end
      end

      def empty_msg
        @query.present? ? "No customers match your search." : "No customers yet."
      end
    end
  end
end
