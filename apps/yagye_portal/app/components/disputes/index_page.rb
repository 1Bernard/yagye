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

    def initialize(tab: "all", disputes: [], pagy: nil)
      @tab     = tab
      @disputes = disputes
      @pagy    = pagy
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
        filter_bar_section
        disputes_table
      end
    end

    private

    def page_header
      div(style: "display:flex;align-items:center;justify-content:space-between;margin-bottom:24px") do
        div do
          p(style: "#{TYPE_CAPTION};margin-bottom:2px") { "Disputes" }
          h1(style: TYPE_DISPLAY) { "Dispute Management" }
        end
        button(type: "button", class: BTN_SECONDARY) do
          render UI::Icon.new(:download, class: ICON_SM)
          "Export"
        end
      end
    end

    def stat_band
      div(class: "#{STAT_BAND} mb-6") do
        stat_cell("Open Disputes",  "0", color: "#f59e0b")
        stat_cell("Won",            "0", color: "#16a34a")
        stat_cell("Lost",           "0", color: "#dc2626")
        stat_cell("SLA Breached",   "0", color: "#dc2626")
      end
    end

    def stat_cell(label, value, color: INK)
      div(class: STAT_CELL) do
        p(style: TYPE_MICRO) { label }
        p(style: "font-size:28px;font-weight:700;color:#{color};font-variant-numeric:tabular-nums;" \
                  "line-height:1;margin-top:6px") { value }
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

    def filter_bar_section
      render UI::FilterBar.new(action: disputes_path) do |f|
        f.search_field name: "q", value: nil, placeholder: "Search by reference or payment ID..."
        f.select_field name: "reason", label: "Reason",
                       options: [
                         [ "All reasons", "" ],
                         [ "Fraud",                "fraud" ],
                         [ "Duplicate charge",     "duplicate" ],
                         [ "Product not received", "not_received" ],
                         [ "Unrecognised",          "unrecognised" ],
                         [ "Other",                "other" ]
                       ]
        f.date_field name: "from", label: "From"
        f.date_field name: "to",   label: "To"
      end
    end

    def disputes_table
      render UI::Datatable.new(records: @disputes, pagy: @pagy,
                               empty_message: empty_message) do |t|
        t.header do
          p(style: TYPE_TITLE) { "#{@tab.capitalize} disputes" }
        end

        t.column("Reference")   { |d| span(style: TYPE_MONO) { d.reference } }
        t.column("Payment")     { |d| span(style: TYPE_MONO) { d.payment_reference } }
        t.column("Amount")      { |d| d.formatted_amount }
        t.column("Reason")      { |d| d.reason.humanize }
        t.column("Status")      { |d| render UI::StatusBadge.new(status: d.status) }
        t.column("SLA")         { |d| sla_badge(d) }
        t.column("Opened")      { |d| d.created_at.strftime("%d %b %Y") }

        t.actions do |d|
          a(href: dispute_path(d), class: DROPDOWN_ITEM) do
            render UI::Icon.new(:eye, class: ICON_SM)
            "Review"
          end
        end
      end
    end

    def sla_badge(dispute)
      span(style: "font-size:12px;font-weight:600;color:#dc2626") { "Overdue" }
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
