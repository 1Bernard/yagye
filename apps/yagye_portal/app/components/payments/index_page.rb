# frozen_string_literal: true

module Payments
  class IndexPage < ApplicationComponent
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
        filter_bar
        payments_table
      end
    end

    private

    def stat_band
      div(style: "display:grid;grid-template-columns:repeat(4,1fr);gap:16px;margin-bottom:20px") do
        stat_cell("Volume (MTD)",       "GHS 0.00", icon: :trending_up,  color: "#3D47F5", tint: "rgba(61,71,245,0.08)")
        stat_cell("Transactions (MTD)", "0",         icon: :layers,       color: "#6d28d9", tint: "rgba(109,40,217,0.08)")
        stat_cell("Pending",            "0",         icon: :clock,        color: "#d97706", tint: "rgba(217,119,6,0.08)")
        stat_cell("Failed",             "0",         icon: :alert_circle, color: "#dc2626", tint: "rgba(220,38,38,0.08)")
      end
    end

    def filter_bar
      render UI::FilterBar.new(action: payments_path) do |f|
        f.search_field name: "q", value: @query, placeholder: "Search reference or customer..."
        f.select_field name: "status", label: "Status", selected: @status_filter,
                       options: [
                         [ "All statuses", "" ],
                         [ "Initiated",    "initiated" ],
                         [ "Processing",   "processing" ],
                         [ "Paid",         "paid" ],
                         [ "Failed",       "failed" ],
                         [ "Refunded",     "refunded" ],
                         [ "Disputed",     "disputed" ]
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
          p(style: TYPE_TITLE) { "Payments" }
          a(href: payments_path(format: :csv, status: status_filter, q: query),
            class: BTN_SECONDARY) do
            render UI::Icon.new(:download, class: ICON_SM)
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
