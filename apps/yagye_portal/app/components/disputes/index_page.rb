# frozen_string_literal: true

module Disputes
  class IndexPage < ApplicationComponent
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
        page_header
        stat_band
        tab_bar
        disputes_table
      end
    end

    private

    def page_header
      div(style: "display:flex;align-items:center;justify-content:space-between;margin-bottom:20px") do
        div do
          p(style: "#{TYPE_CAPTION};margin-bottom:2px") { "Disputes" }
          h1(style: TYPE_DISPLAY) { "Dispute Management" }
        end
      end
    end

    def stat_band
      div(style: "display:grid;grid-template-columns:repeat(4,1fr);gap:16px;margin-bottom:20px") do
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
          div(style: "display:flex;align-items:center;gap:8px") do
            p(style: TYPE_TITLE) { "#{tab.capitalize} disputes" }
            span(style: "background:#f3f4f6;color:#6b7280;border-radius:20px;" \
                        "padding:1px 9px;font-size:11.5px;font-weight:600;line-height:1.6") { total.to_s } if total > 0
          end

          form(action: disputes_path, method: "get",
               style: "display:flex;align-items:center;gap:6px") do
            input(type: "hidden", name: "tab", value: tab)

            div(style: "display:flex;align-items:center;gap:7px;padding:0 11px;" \
                       "border:1px solid #e5e7eb;border-radius:9px;background:#fff;height:32px") do
              span(style: "display:flex;width:12px;height:12px;color:#9ca3af;flex-shrink:0") do
                render UI::Icon.new(:search, class: "w-full h-full")
              end
              input(type: "search", name: "q", value: query,
                    placeholder: "Search reference or payment ID…",
                    style: "border:0;outline:none;background:transparent;font-size:12.5px;" \
                           "color:#374151;width:170px;min-width:0",
                    class: "placeholder:text-gray-400")
            end

            select(name: "reason",
                   style: "border:1px solid #e5e7eb;border-radius:9px;padding:0 10px;" \
                          "font-size:12.5px;font-weight:500;color:#374151;background:#fff;" \
                          "outline:none;cursor:pointer;height:32px") do
              option(value: "", selected: reason.blank?) { "All reasons" }
              [["Fraud","fraud"],["Duplicate charge","duplicate"],
               ["Product not received","not_received"],["Unrecognised","unrecognised"],
               ["Other","other"]].each do |(lbl, val)|
                option(value: val, selected: reason == val) { lbl }
              end
            end

            input(type: "date", name: "from", value: from,
                  style: "border:1px solid #e5e7eb;border-radius:9px;padding:0 10px;" \
                         "font-size:12.5px;color:#374151;background:#fff;" \
                         "outline:none;cursor:pointer;height:32px")

            input(type: "date", name: "to", value: to,
                  style: "border:1px solid #e5e7eb;border-radius:9px;padding:0 10px;" \
                         "font-size:12.5px;color:#374151;background:#fff;" \
                         "outline:none;cursor:pointer;height:32px")

            button(type: "submit",
                   style: "display:inline-flex;align-items:center;padding:0 12px;" \
                          "border:1px solid #e5e7eb;border-radius:9px;font-size:12.5px;" \
                          "font-weight:500;color:#374151;background:#fff;cursor:pointer;" \
                          "height:32px;white-space:nowrap") { plain "Filter" }

            a(href: disputes_path(format: :csv, tab: tab),
              style: "display:inline-flex;align-items:center;gap:5px;padding:0 12px;" \
                     "border:1px solid #e5e7eb;border-radius:9px;font-size:12.5px;" \
                     "font-weight:500;color:#374151;background:#fff;cursor:pointer;" \
                     "height:32px;text-decoration:none;white-space:nowrap") do
              render UI::Icon.new(:download, class: "w-[12px] h-[12px]")
              plain "Export"
            end

            if filters_active
              a(href: disputes_path(tab: tab),
                style: "font-size:12px;color:#9ca3af;text-decoration:none;" \
                       "padding:0 4px;white-space:nowrap") { "Clear" }
            end
          end
        end

        t.column("Reference")   { |d| span(style: TYPE_MONO) { d.reference } }
        t.column("Payment")     { |d| span(style: TYPE_MONO) { d.payment_reference } }
        t.column("Amount")      { |d| d.formatted_amount }
        t.column("Reason")      { |d| d.reason.humanize }
        t.column("Status")      { |d| render UI::StatusBadge.new(status: d.status) }
        t.column("SLA")         { |d| span(style: "font-size:12px;font-weight:600;color:#dc2626") { "Overdue" } }
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
