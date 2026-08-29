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
      div(style: "display:grid;grid-template-columns:repeat(4,1fr);gap:16px;margin-bottom:20px") do
        stat_cell("Volume (MTD)",       "GHS 0.00", icon: :trending_up,  color: "#3D47F5", tint: "rgba(61,71,245,0.08)")
        stat_cell("Transactions (MTD)", "0",         icon: :layers,       color: "#6d28d9", tint: "rgba(109,40,217,0.08)")
        stat_cell("Pending",            "0",         icon: :clock,        color: "#d97706", tint: "rgba(217,119,6,0.08)")
        stat_cell("Failed",             "0",         icon: :alert_circle, color: "#dc2626", tint: "rgba(220,38,38,0.08)")
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
          div(style: "display:flex;align-items:center;gap:8px") do
            p(style: TYPE_TITLE) { "Payments" }
            span(style: "background:#f3f4f6;color:#6b7280;border-radius:20px;" \
                        "padding:1px 9px;font-size:11.5px;font-weight:600;line-height:1.6") { total.to_s } if total > 0
          end

          form(action: payments_path, method: "get",
               style: "display:flex;align-items:center;gap:6px",
               data: { controller: "filter-form", filter_form_target: "form" }) do
            div(style: "display:flex;align-items:center;gap:7px;padding:0 11px;" \
                       "border:1px solid #e5e7eb;border-radius:9px;background:#fff;height:32px") do
              span(style: "display:flex;width:12px;height:12px;color:#9ca3af;flex-shrink:0") do
                render UI::Icon.new(:search, class: "w-full h-full")
              end
              input(type: "search", name: "q", value: query,
                    placeholder: "Search reference or customer…",
                    style: "border:0;outline:none;background:transparent;font-size:12.5px;" \
                           "color:#374151;width:180px;min-width:0",
                    class: "placeholder:text-gray-400")
            end

            select(name: "status",
                   style: "border:1px solid #e5e7eb;border-radius:9px;padding:0 10px;" \
                          "font-size:12.5px;font-weight:500;color:#374151;background:#fff;" \
                          "outline:none;cursor:pointer;height:32px",
                   data: { action: "change->filter-form#submit" }) do
              option(value: "", selected: status_filter.blank?) { "All statuses" }
              [["Initiated","initiated"],["Processing","processing"],["Paid","paid"],
               ["Failed","failed"],["Refunded","refunded"],["Disputed","disputed"]].each do |(lbl, val)|
                option(value: val, selected: status_filter == val) { lbl }
              end
            end

            button(type: "submit",
                   style: "display:inline-flex;align-items:center;gap:5px;padding:0 12px;" \
                          "border:1px solid #e5e7eb;border-radius:9px;font-size:12.5px;" \
                          "font-weight:500;color:#374151;background:#fff;cursor:pointer;" \
                          "height:32px;white-space:nowrap") do
              render UI::Icon.new(:filter, class: "w-[12px] h-[12px]")
              plain "Filter"
            end

            if can_export
              a(href: payments_path(format: :csv, status: status_filter, q: query),
                style: "display:inline-flex;align-items:center;gap:5px;padding:0 12px;" \
                       "border:1px solid #e5e7eb;border-radius:9px;font-size:12.5px;" \
                       "font-weight:500;color:#374151;background:#fff;cursor:pointer;" \
                       "height:32px;text-decoration:none;white-space:nowrap") do
                render UI::Icon.new(:download, class: "w-[12px] h-[12px]")
                plain "Export"
              end
            end

            if query.present? || status_filter.present?
              a(href: payments_path,
                style: "font-size:12px;color:#9ca3af;text-decoration:none;" \
                       "padding:0 4px;white-space:nowrap") { "Clear" }
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
