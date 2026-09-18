# frozen_string_literal: true

module Disputes
  class IndexView < ApplicationComponent
    include UI::Theme

    TABS = [
      { key: "all",  label: "All"  },
      { key: "open", label: "Open" },
      { key: "won",  label: "Won"  },
      { key: "lost", label: "Lost" }
    ].freeze

    def initialize(tab: "all", disputes: [], pagy: nil, query: nil, reason: nil,
                   date_from: nil, date_to: nil, stats: {})
      @tab       = tab
      @disputes  = disputes
      @pagy      = pagy
      @query     = query
      @reason    = reason
      @date_from = date_from
      @date_to   = date_to
      @stats     = stats
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
        stat_cell("Open Disputes", @stats[:open].to_s,         icon: :flag,         color: AMBER, tint: TINT_AMBER)
        stat_cell("Won",           @stats[:won].to_s,          icon: :check_circle, color: GREEN, tint: TINT_GREEN)
        stat_cell("Lost",          @stats[:lost].to_s,         icon: :alert_circle, color: RED,   tint: TINT_RED)
        stat_cell("SLA Breached",  @stats[:sla_breached].to_s, icon: :clock,        color: RED,   tint: TINT_RED)
      end
    end

    def tab_bar
      render UI::Tabs.new do |t|
        TABS.each do |tab|
          t.tab tab[:label],
                href:   disputes_path(tab: tab[:key]),
                active: @tab == tab[:key]
        end
      end
    end

    def disputes_table
      offset = @pagy ? @pagy.offset : 0

      render UI::Datatable.new(records: @disputes, pagy: @pagy,
                               empty_message: empty_message) do |t|
        t.header { toolbar_content }

        t.column("#", class: "text-gray-400 tabular-nums text-right w-8") do |_, i|
          plain((offset + i + 1).to_s)
        end
        t.column("Amount")    { |d| plain d.formatted_amount }
        t.column("Reason")    { |d| plain d.reason.humanize }
        t.column("Reference", class: "font-mono text-[11.5px]") { |d| plain d.reference }
        t.column("Payment",   class: "font-mono text-[11.5px]") { |d| plain d.payment_reference }
        t.column("Status")    { |d| render UI::StatusBadge.new(status: d.status) }
        t.column("SLA") do |d|
          if d.network_deadline.present? && d.open?
            today   = Date.current.to_s
            overdue = d.network_deadline < today
            due_str = Date.parse(d.network_deadline).strftime("%d %b") rescue d.network_deadline
            cls     = overdue ? "text-[12px] font-semibold text-red-600" : "text-[12px] text-gray-500"
            span(class: cls) { plain(overdue ? "Overdue" : "Due #{due_str}") }
          else
            span(class: TYPE_CAPTION) { plain "—" }
          end
        end
        t.column("Opened") { |d| plain d.created_at.strftime("%d %b %Y") }

        t.actions do |d|
          a(href: dispute_path(d), class: DROPDOWN_ITEM) do
            render UI::Icon.new(:eye, class: ICON_SM)
            plain "Review"
          end
        end
      end
    end

    # ── Toolbar ───────────────────────────────────────────────────────────────

    def toolbar_content
      filter_count = [ @reason.present?, @date_from.present?, @date_to.present? ].count(true)

      form(action: disputes_path, method: "get",
           data: { controller: "filter-form", filter_form_target: "form" }) do
        input(type: "hidden", name: "tab", value: @tab)
        div(class: FILTER_SEARCH_WRAP) do
          span(class: "flex w-[13px] h-[13px] text-gray-400 flex-shrink-0") do
            render UI::Icon.new(:search, class: "w-full h-full")
          end
          input(type: "search", name: "q", value: @query,
                placeholder: "Search reference or payment ID…",
                class: FILTER_SEARCH_INPUT)
        end
      end

      div(class: "flex items-center gap-2") do
        export_dropdown
        filter_btn(filter_count)
      end
    end

    def export_dropdown
      base = { tab: @tab, q: @query, reason: @reason,
               from: @date_from, to: @date_to }.reject { |_, v| v.blank? }

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
          a(href: disputes_path(base.merge(format: :csv)),  class: DROPDOWN_ITEM) do
            render UI::Icon.new(:file, class: ICON_SM)
            plain "CSV"
          end
          a(href: disputes_path(base.merge(format: :xlsx)), class: DROPDOWN_ITEM) do
            render UI::Icon.new(:file, class: ICON_SM)
            plain "Excel (.xlsx)"
          end
          a(href: disputes_path(base.merge(format: :pdf)),  class: DROPDOWN_ITEM) do
            render UI::Icon.new(:file, class: ICON_SM)
            plain "PDF"
          end
        end
      end
    end

    def filter_btn(filter_count)
      a(href: filter_disputes_path(tab: @tab, q: @query, reason: @reason,
                                   from: @date_from, to: @date_to),
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
      case @tab
      when "open" then "No open disputes at the moment."
      when "won"  then "No won disputes yet."
      when "lost" then "No lost disputes."
      else             "No disputes have been raised yet."
      end
    end
  end
end
