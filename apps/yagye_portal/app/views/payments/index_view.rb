# frozen_string_literal: true

module Payments
  class IndexView < ApplicationComponent
    include UI::Theme

    def initialize(payments:, pagy:, can_view_pii: false, can_export: false,
                   status_filter: nil, method_filter: nil, from: nil, to: nil, query: nil)
      @payments       = payments
      @pagy           = pagy
      @can_view_pii   = can_view_pii
      @can_export     = can_export
      @status_filter  = status_filter
      @method_filter  = method_filter
      @from           = from
      @to             = to
      @query          = query
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
      can_view_pii = @can_view_pii
      offset       = @pagy.offset

      render UI::Datatable.new(records: @payments, pagy: @pagy, empty_message: empty_message) do |t|
        t.header { toolbar_content }

        t.column("#", class: "text-gray-400 tabular-nums text-right w-8") do |_, i|
          plain((offset + i + 1).to_s)
        end
        t.column("Amount", class: "text-right tabular-nums font-semibold") { |p| p.formatted_amount }
        t.column("Customer") { |p| can_view_pii ? p.customer_display : (p.masked_msisdn || "—") }
        t.column("Method") do |p|
          div(class: "flex items-center gap-1.5") do
            span(class: "w-3.5 h-3.5 text-gray-400 flex-shrink-0") do
              render UI::Icon.new(p.method_icon, class: "w-full h-full")
            end
            span { plain p.method_label }
          end
        end
        t.column("Reference", class: "font-mono text-[11.5px]") do |p|
          plain(p.reference.presence || p.core_payment_id&.first(12) || "—")
        end
        t.column("Status")  { |p| render UI::StatusBadge.new(status: p.status) }
        t.column("Date")    { |p| p.created_at.strftime("%d %b %Y, %H:%M") }

        t.actions do |p|
          a(href: payment_path(p), class: DROPDOWN_ITEM) do
            render UI::Icon.new(:eye, class: ICON_SM)
            plain "View"
          end
        end
      end
    end

    # ── Toolbar ───────────────────────────────────────────────────────────────

    def toolbar_content
      filter_count = [ @status_filter.present?, @method_filter.present?,
                       @from.present?, @to.present? ].count(true)

      form(action: payments_path, method: "get",
           data: { controller: "filter-form", filter_form_target: "form" }) do
        div(class: FILTER_SEARCH_WRAP) do
          span(class: "flex w-[13px] h-[13px] text-gray-400 flex-shrink-0") do
            render UI::Icon.new(:search, class: "w-full h-full")
          end
          input(type: "search", name: "q", value: @query,
                placeholder: "Search reference or customer…",
                class: FILTER_SEARCH_INPUT)
        end
      end

      div(class: "flex items-center gap-2") do
        export_dropdown if @can_export
        filter_btn(filter_count)
      end
    end

    def export_dropdown
      base = { q: @query, status: @status_filter, method: @method_filter,
               from: @from, to: @to }.reject { |_, v| v.blank? }

      div(class: "relative", data: { controller: "dropdown" }) do
        button(type: "button",
               class: "inline-flex items-center gap-[5px] px-3 h-8 border border-gray-200 rounded-[9px] " \
                      "text-[12.5px] font-medium text-gray-600 bg-white cursor-pointer transition-colors " \
                      "hover:border-gray-400 hover:text-gray-800",
               data: { action: "click->dropdown#toggle" }) do
          render UI::Icon.new(:download, class: "w-3 h-3")
          plain "Export"
          render UI::Icon.new(:chev, class: "w-3 h-3 ml-px text-gray-400")
        end
        div(class: "#{DROPDOWN_MENU} top-full mt-1 right-0 min-w-[170px]",
            data: { dropdown_target: "menu" }) do
          p(class: DROPDOWN_TITLE) { plain "Export as" }
          a(href: payments_path(base.merge(format: :csv)),  class: DROPDOWN_ITEM) do
            render UI::Icon.new(:file, class: ICON_SM)
            plain "CSV"
          end
          a(href: payments_path(base.merge(format: :xlsx)), class: DROPDOWN_ITEM) do
            render UI::Icon.new(:file, class: ICON_SM)
            plain "Excel (.xlsx)"
          end
          a(href: payments_path(base.merge(format: :pdf)),  class: DROPDOWN_ITEM) do
            render UI::Icon.new(:file, class: ICON_SM)
            plain "PDF"
          end
        end
      end
    end

    def filter_btn(filter_count)
      a(href: filter_payments_path(q: @query, status: @status_filter,
                                   method: @method_filter, from: @from, to: @to),
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

    def empty_message
      if @status_filter.present? || @method_filter.present? || @query.present?
        "No payments match those filters."
      else
        "Payments will appear here once transactions are processed."
      end
    end
  end
end
