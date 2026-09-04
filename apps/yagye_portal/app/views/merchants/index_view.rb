# frozen_string_literal: true

module Merchants
  class IndexView < ApplicationComponent
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
        stat_band
        merchants_table
      end
    end

    private

    def stat_band
      render UI::Grid.new(columns: 4) do
        stat_cell("Active Merchants", "0", icon: :check_circle, color: GREEN, tint: TINT_GREEN)
        stat_cell("Pending KYB",      "0", icon: :clock,        color: AMBER, tint: TINT_AMBER)
        stat_cell("Suspended",        "0", icon: :alert_circle, color: RED,   tint: TINT_RED)
        stat_cell("Onboarded (30d)",  "0", icon: :trending_up,  color: BRAND, tint: TINT_BRAND)
      end
    end

    def merchants_table
      status = @status
      query  = @query
      total  = @pagy ? @pagy.count : @merchants.size

      render UI::Datatable.new(records: @merchants, pagy: @pagy,
                               empty_message: "No merchants registered yet.") do |t|
        t.header do
          div(style: "display:flex;align-items:center;gap:8px") do
            p(class: TYPE_TITLE) { "All merchants" }
            span(style: "background:#f3f4f6;color:#6b7280;border-radius:20px;" \
                        "padding:1px 9px;font-size:11.5px;font-weight:600;line-height:1.6") { total.to_s } if total > 0
          end

          form(action: merchants_path, method: "get",
               style: "display:flex;align-items:center;gap:6px",
               data: { controller: "filter-form", filter_form_target: "form" }) do
            div(style: "display:flex;align-items:center;gap:7px;padding:0 11px;" \
                       "border:1px solid #e5e7eb;border-radius:9px;background:#fff;height:32px") do
              span(style: "display:flex;width:12px;height:12px;color:#9ca3af;flex-shrink:0") do
                render UI::Icon.new(:search, class: "w-full h-full")
              end
              input(type: "search", name: "q", value: query,
                    placeholder: "Search business name or code…",
                    style: "border:0;outline:none;background:transparent;font-size:12.5px;" \
                           "color:#374151;width:180px;min-width:0",
                    class: "placeholder:text-gray-400")
            end

            select(name: "status",
                   style: "border:1px solid #e5e7eb;border-radius:9px;padding:0 10px;" \
                          "font-size:12.5px;font-weight:500;color:#374151;background:#fff;" \
                          "outline:none;cursor:pointer;height:32px",
                   data: { action: "change->filter-form#submit" }) do
              option(value: "", selected: status.blank?) { "All statuses" }
              [ [ "Active", "active" ], [ "Pending KYB", "pending_kyb" ], [ "Under review", "under_review" ],
               [ "Suspended", "suspended" ], [ "Rejected", "rejected" ] ].each do |(lbl, val)|
                option(value: val, selected: status == val) { lbl }
              end
            end

            select(name: "country",
                   style: "border:1px solid #e5e7eb;border-radius:9px;padding:0 10px;" \
                          "font-size:12.5px;font-weight:500;color:#374151;background:#fff;" \
                          "outline:none;cursor:pointer;height:32px",
                   data: { action: "change->filter-form#submit" }) do
              option(value: "") { "All countries" }
              [ [ "Ghana", "GH" ], [ "Nigeria", "NG" ], [ "Kenya", "KE" ], [ "Côte d'Ivoire", "CI" ] ].each do |(lbl, val)|
                option(value: val) { lbl }
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

            a(href: merchants_path(format: :csv, status: status, q: query),
              style: "display:inline-flex;align-items:center;gap:5px;padding:0 12px;" \
                     "border:1px solid #e5e7eb;border-radius:9px;font-size:12.5px;" \
                     "font-weight:500;color:#374151;background:#fff;cursor:pointer;" \
                     "height:32px;text-decoration:none;white-space:nowrap") do
              render UI::Icon.new(:download, class: "w-[12px] h-[12px]")
              plain "Export"
            end

            if query.present? || status.present?
              a(href: merchants_path,
                style: "font-size:12px;color:#9ca3af;text-decoration:none;" \
                       "padding:0 4px;white-space:nowrap") { "Clear" }
            end
          end
        end

        t.column("Business") do |m|
          div(style: "display:flex;align-items:center;gap:10px") do
            render UI::Avatar.new(m.legal_name&.first(2)&.upcase || "??", size: :sm)
            div do
              p(class: TYPE_BODY_MD) { m.legal_name }
              p(class: TYPE_CAPTION) { m.submitted_by_email }
            end
          end
        end
        t.column("Code")         { |m| span(class: TYPE_MONO) { m.merchant_code } }
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
