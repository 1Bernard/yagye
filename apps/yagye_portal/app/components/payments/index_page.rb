# frozen_string_literal: true

module Payments
  class IndexPage < ApplicationComponent
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
        filter_bar
        payments_table
      end
    end

    private

    def stat_band
      div(class: "#{UI::Theme::STAT_BAND} mb-6") do
        stat_cell("Volume (MTD)", "GHS 0.00")
        stat_cell("Transactions (MTD)", "0")
        stat_cell("Pending", "0", delta: "0%", up: true)
        stat_cell("Failed", "0", delta: "0%", up: false)
      end
    end

    def stat_cell(label, value, delta: nil, up: nil)
      div(class: UI::Theme::STAT_CELL) do
        p(class: UI::Theme::TEXT_LABEL) { label }
        p(class: "#{UI::Theme::TEXT_VALUE} text-2xl font-bold mt-1 tabular-nums") { value }
        if delta
          span(class: "text-xs mt-1 #{up ? UI::Theme::STAT_UP : UI::Theme::STAT_DOWN}") do
            render UI::Icon.new(up ? :trending_up : :trending_down, class: "inline w-3 h-3 mr-0.5")
            plain delta
          end
        end
      end
    end

    def filter_bar
      render UI::FilterBar.new(action: payments_path) do |f|
        f.search_field name: "q", value: @query, placeholder: "Search reference or customer..."
        f.select_field name: "status", label: "Status", selected: @status_filter,
                       options: [
                         [ "All statuses", "" ],
                         [ "Initiated", "initiated" ],
                         [ "Processing", "processing" ],
                         [ "Paid", "paid" ],
                         [ "Failed", "failed" ],
                         [ "Refunded", "refunded" ],
                         [ "Disputed", "disputed" ]
                       ]
      end
    end

    def payments_table
      can_view_pii  = @can_view_pii
      can_export    = @can_export
      status_filter = @status_filter
      query         = @query

      render UI::Datatable.new(records: @payments, pagy: @pagy, empty_message: empty_message) do |t|
        t.header do
          h2(class: UI::Theme::TEXT_H2) { "Payments" }
          a(href: payments_path(format: :csv, status: status_filter, q: query),
            class: UI::Theme::BTN_SECONDARY) do
            render UI::Icon.new(:download, class: UI::Theme::ICON_SM)
            plain "Export"
          end if can_export
        end

        t.column("Reference") { |p| p.reference.presence || p.core_payment_id&.first(12) }
        t.column("Customer")  { |p| can_view_pii ? (p.customer_msisdn || "—") : p.masked_msisdn }
        t.column("Amount", class: "text-right tabular-nums font-medium") { |p| p.formatted_amount }
        t.column("Status")   { |p| render UI::StatusBadge.new(status: p.status) }
        t.column("Provider") { |p| p.provider_label }
        t.column("Date")     { |p| p.created_at.strftime("%d %b %Y, %H:%M") }

        t.actions do |p|
          a(href: payment_path(p), class: UI::Theme::DROPDOWN_ITEM) do
            render UI::Icon.new(:eye, class: UI::Theme::ICON_SM)
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
