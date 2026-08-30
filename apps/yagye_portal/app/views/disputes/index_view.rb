# frozen_string_literal: true

module Disputes
  class IndexView < ApplicationComponent
    include UI::Theme

    TABS = [
      { key: "all",  label: "All" },
      { key: "open", label: "Open" },
      { key: "won",  label: "Won" },
      { key: "lost", label: "Lost" }
    ].freeze

    def initialize(tab: "all", disputes: [], pagy: nil, query: nil, reason: nil,
                   date_from: nil, date_to: nil)
      @tab      = tab
      @disputes = disputes
      @pagy     = pagy
      @query    = query
      @reason   = reason
      @date_from = date_from
      @date_to   = date_to
    end

    def view_template
      render Layout::Shell.new(
        active_nav: :disputes,
        title:      "Disputes",
        breadcrumbs: [ { label: "Disputes" } ]
      ) do
        stat_band
        tab_bar
        disputes_table
      end
    end

    private

    def stat_band
      render UI::Grid.new(columns: 4) do
        stat_cell("Open Disputes", "0", icon: :flag,         color: "#d97706", tint: "rgba(217,119,6,0.08)")
        stat_cell("Won",           "0", icon: :check_circle, color: "#16a34a", tint: "rgba(22,163,74,0.08)")
        stat_cell("Lost",          "0", icon: :alert_circle, color: "#dc2626", tint: "rgba(220,38,38,0.08)")
        stat_cell("SLA Breached",  "0", icon: :clock,        color: "#dc2626", tint: "rgba(220,38,38,0.08)")
      end
    end

    def tab_bar
      render UI::Tabs.new do |t|
        TABS.each do |tab|
          t.tab tab[:label],
                href: disputes_path(tab: tab[:key]),
                active: @tab == tab[:key]
        end
      end
    end

    def disputes_table
      tab    = @tab
      query  = @query
      reason = @reason
      from   = @date_from
      to     = @date_to
      total  = @pagy ? @pagy.count : @disputes.size

      filters_active = query.present? || reason.present? || from.present? || to.present?

      render UI::Datatable.new(records: @disputes, pagy: @pagy,
                               empty_message: empty_message) do |t|
        t.header do
          div(class: "flex items-center gap-2") do
            p(class: TYPE_TITLE) { plain "#{tab.capitalize} disputes" }
            span(class: "bg-gray-100 text-gray-500 rounded-full px-[9px] py-[1px] text-[11.5px] font-semibold leading-[1.6]") { plain total.to_s } if total > 0
          end

          form(action: disputes_path, method: "get",
               class: "flex items-center gap-1.5",
               data: { controller: "filter-form", filter_form_target: "form" }) do
            input(type: "hidden", name: "tab", value: tab)

            div(class: "flex items-center gap-2 px-3 h-8 border border-gray-200 rounded-[9px] bg-white") do
              span(class: "flex w-3 h-3 text-gray-400 flex-shrink-0") do
                render UI::Icon.new(:search, class: "w-full h-full")
              end
              input(type: "search", name: "q", value: query,
                    placeholder: "Search reference or payment ID…",
                    class: "border-0 outline-none bg-transparent text-[12.5px] text-gray-700 w-[170px] min-w-0 placeholder:text-gray-400")
            end

            select(name: "reason",
                   class: "h-8 border border-gray-200 rounded-[9px] px-[10px] text-[12.5px] font-medium text-gray-700 bg-white outline-none cursor-pointer",
                   data: { action: "change->filter-form#submit" }) do
              option(value: "", selected: reason.blank?) { plain "All reasons" }
              [ [ "Fraud", "fraud" ], [ "Duplicate charge", "duplicate" ],
               [ "Product not received", "not_received" ], [ "Unrecognised", "unrecognised" ],
               [ "Other", "other" ] ].each do |(lbl, val)|
                option(value: val, selected: reason == val) { plain lbl }
              end
            end

            input(type: "date", name: "from", value: from,
                  class: "h-8 border border-gray-200 rounded-[9px] px-[10px] text-[12.5px] text-gray-700 bg-white outline-none cursor-pointer",
                  data: { action: "change->filter-form#submit" })

            input(type: "date", name: "to", value: to,
                  class: "h-8 border border-gray-200 rounded-[9px] px-[10px] text-[12.5px] text-gray-700 bg-white outline-none cursor-pointer",
                  data: { action: "change->filter-form#submit" })

            render UI::Button.new(variant: :secondary, type: "submit") do
              render UI::Icon.new(:filter, class: "w-[12px] h-[12px]")
              plain "Filter"
            end

            render UI::Button.new(variant: :secondary, href: disputes_path(format: :csv, tab: tab)) do
              render UI::Icon.new(:download, class: "w-[12px] h-[12px]")
              plain "Export"
            end

            if filters_active
              a(href: disputes_path(tab: tab), class: "text-[12px] text-gray-400 no-underline px-1 whitespace-nowrap") { plain "Clear" }
            end
          end
        end

        t.column("Reference")   { |d| span(class: TYPE_MONO) { d.reference } }
        t.column("Payment")     { |d| span(class: TYPE_MONO) { d.payment_reference } }
        t.column("Amount")      { |d| d.formatted_amount }
        t.column("Reason")      { |d| d.reason.humanize }
        t.column("Status")      { |d| render UI::StatusBadge.new(status: d.status) }
        t.column("SLA")         { |d| span(class: "text-[12px] font-semibold text-red-600") { plain "Overdue" } }
        t.column("Opened")      { |d| d.created_at.strftime("%d %b %Y") }

        t.actions do |d|
          a(href: dispute_path(d), class: DROPDOWN_ITEM) do
            render UI::Icon.new(:eye, class: ICON_SM)
            "Review"
          end
        end
      end
    end

    def empty_message
      case @tab
      when "open"  then "No open disputes at the moment."
      when "won"   then "No won disputes yet."
      when "lost"  then "No lost disputes."
      else              "No disputes have been raised yet."
      end
    end
  end
end
