# frozen_string_literal: true

module Payments
  class IndexView < ApplicationComponent
    include UI::Theme

    def initialize(payments:, pagy:, can_view_pii: false, can_export: false,
                   status_filter: nil, query: nil)
      @payments      = payments
      @pagy          = pagy
      @can_view_pii  = can_view_pii
      @can_export    = can_export
      @status_filter = status_filter
      @query         = query
    end

    def view_template
      render Layout::Shell.new(
        active_nav: :payments,
        title: "Payments",
        subtitle: "All transactions processed through your account"
      ) do
        stat_band
        payments_table
      end
    end

    private

    def stat_band
      render UI::Grid.new(columns: 4) do
        stat_cell("Volume (MTD)",       "GHS 0.00", icon: :trending_up,  color: BRAND,  tint: TINT_BRAND)
        stat_cell("Transactions (MTD)", "0",         icon: :layers,       color: PURPLE, tint: TINT_PURPLE)
        stat_cell("Pending",            "0",         icon: :clock,        color: AMBER,  tint: TINT_AMBER)
        stat_cell("Failed",             "0",         icon: :alert_circle, color: RED,    tint: TINT_RED)
      end
    end

    def payments_table
      can_view_pii  = @can_view_pii
      can_export    = @can_export
      status_filter = @status_filter
      query         = @query
      total         = @pagy.count

      render UI::Datatable.new(records: @payments, pagy: @pagy, empty_message: empty_message) do |t|
        t.header do
          div(class: "flex items-center gap-2") do
            p(class: TYPE_TITLE) { plain "Payments" }
            span(class: "bg-gray-100 text-gray-500 rounded-full px-[9px] py-[1px] text-[11.5px] font-semibold leading-[1.6]") { plain total.to_s } if total > 0
          end

          form(action: payments_path, method: "get",
               class: "flex items-center gap-1.5",
               data: { controller: "filter-form", filter_form_target: "form" }) do
            div(class: "flex items-center gap-2 px-3 h-8 border border-gray-200 rounded-[9px] bg-white") do
              span(class: "flex w-3 h-3 text-gray-400 flex-shrink-0") do
                render UI::Icon.new(:search, class: "w-full h-full")
              end
              input(type: "search", name: "q", value: query,
                    placeholder: "Search reference or customer…",
                    class: "border-0 outline-none bg-transparent text-[12.5px] text-gray-700 w-[180px] min-w-0 placeholder:text-gray-400")
            end

            select(name: "status",
                   class: "h-8 border border-gray-200 rounded-[9px] px-[10px] text-[12.5px] font-medium text-gray-700 bg-white outline-none cursor-pointer",
                   data: { action: "change->filter-form#submit" }) do
              option(value: "", selected: status_filter.blank?) { plain "All statuses" }
              [ [ "Initiated", "initiated" ], [ "Processing", "processing" ], [ "Paid", "paid" ],
               [ "Failed", "failed" ], [ "Refunded", "refunded" ], [ "Disputed", "disputed" ] ].each do |(lbl, val)|
                option(value: val, selected: status_filter == val) { plain lbl }
              end
            end

            render UI::Button.new(variant: :secondary, type: "submit") do
              render UI::Icon.new(:filter, class: "w-[12px] h-[12px]")
              plain "Filter"
            end

            if can_export
              render UI::Button.new(variant: :secondary, href: payments_path(format: :csv, status: status_filter, q: query)) do
                render UI::Icon.new(:download, class: "w-[12px] h-[12px]")
                plain "Export"
              end
            end

            if query.present? || status_filter.present?
              a(href: payments_path, class: "text-[12px] text-gray-400 no-underline px-1 whitespace-nowrap") { plain "Clear" }
            end
          end
        end

        t.column("Reference") { |p| p.reference.presence || p.core_payment_id&.first(12) }
        t.column("Customer")  { |p| can_view_pii ? (p.customer_msisdn || "—") : p.masked_msisdn }
        t.column("Amount", class: "text-right tabular-nums font-medium") { |p| p.formatted_amount }
        t.column("Status")   { |p| render UI::StatusBadge.new(status: p.status) }
        t.column("Provider") { |p| p.provider_label }
        t.column("Date")     { |p| p.created_at.strftime("%d %b %Y, %H:%M") }

        t.actions do |p|
          a(href: payment_path(p), class: DROPDOWN_ITEM) do
            render UI::Icon.new(:eye, class: ICON_SM)
            plain "View"
          end
        end
      end
    end

    def empty_message
      if @status_filter.present? || @query.present?
        "No payments match those filters."
      else
        "Payments will appear here once transactions are processed."
      end
    end
  end
end
