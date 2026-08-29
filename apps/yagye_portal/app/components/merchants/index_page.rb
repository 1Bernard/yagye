# frozen_string_literal: true

module Merchants
  class IndexPage < ApplicationComponent
    include UI::Theme

    def initialize(merchants: [], pagy: nil, status: nil, query: nil)
      @merchants = merchants
      @pagy      = pagy
      @status    = status
      @query     = query
    end

    def view_template
      render Layout::Shell.new(
        active_nav: :merchants,
        title:      "Merchants",
        breadcrumbs: [ { label: "Merchants" } ]
      ) do
        page_header
        stat_band
        filter_bar_section
        merchants_table
      end
    end

    private

    def page_header
      div(style: "display:flex;align-items:center;justify-content:space-between;margin-bottom:24px") do
        div do
          p(style: "#{TYPE_CAPTION};margin-bottom:2px") { "Operations" }
          h1(style: TYPE_DISPLAY) { "Merchants" }
        end
        button(type: "button", class: BTN_SECONDARY) do
          render UI::Icon.new(:download, class: ICON_SM)
          "Export"
        end
      end
    end

    def stat_band
      div(class: "#{STAT_BAND} mb-6") do
        stat_cell("Active Merchants",   "0", color: "#16a34a")
        stat_cell("Pending KYB",        "0", color: "#f59e0b")
        stat_cell("Suspended",          "0", color: "#dc2626")
        stat_cell("Onboarded (30d)",    "0")
      end
    end

    def filter_bar_section
      render UI::FilterBar.new(action: merchants_path) do |f|
        f.search_field name: "q", value: @query, placeholder: "Search business name or code..."
        f.select_field name: "status", label: "Status",
                       selected: @status,
                       options: [
                         [ "All statuses",    "" ],
                         [ "Active",          "active" ],
                         [ "Pending KYB",     "pending_kyb" ],
                         [ "Under review",    "under_review" ],
                         [ "Suspended",       "suspended" ],
                         [ "Rejected",        "rejected" ]
                       ]
        f.select_field name: "country", label: "Country",
                       options: [
                         [ "All countries", "" ],
                         [ "Ghana",         "GH" ],
                         [ "Nigeria",       "NG" ],
                         [ "Kenya",         "KE" ],
                         [ "Côte d'Ivoire", "CI" ]
                       ]
      end
    end

    def merchants_table
      render UI::Datatable.new(records: @merchants, pagy: @pagy,
                               empty_message: "No merchants registered yet.") do |t|
        t.header do
          p(style: TYPE_TITLE) { "All merchants" }
        end

        t.column("Business") do |m|
          div(style: "display:flex;align-items:center;gap:10px") do
            render UI::Avatar.new(m.legal_name&.first(2)&.upcase || "??", size: :sm)
            div do
              p(style: TYPE_BODY_MD) { m.legal_name }
              p(style: TYPE_CAPTION) { m.submitted_by_email }
            end
          end
        end
        t.column("Code")         { |m| span(style: TYPE_MONO) { m.merchant_code } }
        t.column("Country")      { |m| m.country }
        t.column("KYB Status")   { |m| render UI::StatusBadge.new(status: m.status) }
        t.column("Volume (MTD)") { |m| span(style: "font-size:13px;color:#{SUBTLE_TEXT}") { "—" } }
        t.column("Applied")      { |m| m.last_applied_at&.strftime("%d %b %Y") || "—" }

        t.actions do |m|
          a(href: merchant_path(m), class: DROPDOWN_ITEM) do
            render UI::Icon.new(:eye, class: ICON_SM)
            "View"
          end
        end
      end
    end

  end
end
