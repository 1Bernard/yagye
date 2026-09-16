# frozen_string_literal: true

module Merchants
  class IndexView < ApplicationComponent
    include UI::Theme

    def initialize(merchants: [], pagy: nil, status: nil, query: nil, country: nil, stats: {}, mtd_volumes: {})
      @merchants = merchants
      @pagy      = pagy
      @status    = status
      @query     = query
      @country   = country
      @stats       = stats
      @mtd_volumes = mtd_volumes
    end

    def view_template
      render Layout::Shell.new(
        active_nav: :merchants,
        title:      "Merchants",
        breadcrumbs: [ { label: "Merchants" } ]
      ) do
        render UI::PageHeader.new(title: "Merchants", subtitle: "All registered businesses on the platform.")
        stat_band
        merchants_table
      end
    end

    private

    # ── Stat band ────────────────────────────────────────────────────────────────

    def stat_band
      render UI::Grid.new(columns: 4) do
        stat_cell("Active Merchants", @stats[:active].to_s,       icon: :check_circle, color: GREEN, tint: TINT_GREEN)
        stat_cell("Pending KYB",      @stats[:pending_kyb].to_s,  icon: :clock,        color: AMBER, tint: TINT_AMBER)
        stat_cell("Suspended",        @stats[:suspended].to_s,    icon: :alert_circle, color: RED,   tint: TINT_RED)
        stat_cell("Onboarded (30d)",  @stats[:onboarded_30d].to_s, icon: :trending_up, color: BRAND, tint: TINT_BRAND)
      end
    end

    # ── Toolbar ──────────────────────────────────────────────────────────────────

    def toolbar_content
      form(action: merchants_path, method: "get",
           data: { controller: "filter-form", filter_form_target: "form" }) do
        div(class: FILTER_SEARCH_WRAP) do
          span(class: "flex w-[13px] h-[13px] text-gray-400 flex-shrink-0") do
            render UI::Icon.new(:search, class: "w-full h-full")
          end
          input(type: "search", name: "q", value: @query,
                placeholder: "Search business name or code…",
                class: FILTER_SEARCH_INPUT)
        end
      end

      div(class: "flex items-center gap-2") do
        inline_filters
        export_dropdown
      end
    end

    def inline_filters
      form(action: merchants_path, method: "get",
           class: "flex items-center gap-2",
           data: { controller: "filter-form", filter_form_target: "form" }) do
        input(type: "hidden", name: "q", value: @query)

        select_cls = "h-8 border border-gray-200 rounded-[9px] px-2.5 text-[12.5px] font-medium " \
                     "text-gray-600 bg-white outline-none cursor-pointer hover:border-gray-400 " \
                     "transition-colors"

        select(name: "status", class: select_cls,
               data: { action: "change->filter-form#submit" }) do
          option(value: "", selected: @status.blank?) { plain "All statuses" }
          [ [ "Active", "approved" ], [ "Pending KYB", "submitted" ],
            [ "Under review", "under_review" ], [ "Rejected", "rejected" ] ].each do |(lbl, val)|
            option(value: val, selected: @status == val) { plain lbl }
          end
        end

        select(name: "country", class: select_cls,
               data: { action: "change->filter-form#submit" }) do
          option(value: "", selected: @country.blank?) { plain "All countries" }
          [ [ "Ghana", "GH" ], [ "Nigeria", "NG" ], [ "Kenya", "KE" ],
            [ "Côte d'Ivoire", "CI" ] ].each do |(lbl, val)|
            option(value: val, selected: @country == val) { plain lbl }
          end
        end

        if @query.present? || @status.present? || @country.present?
          a(href: merchants_path,
            class: "text-[12px] text-gray-400 hover:text-gray-600 no-underline px-1 transition-colors") do
            plain "Clear"
          end
        end
      end
    end

    def export_dropdown
      base = { q: @query, status: @status, country: @country }.reject { |_, v| v.blank? }

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
          a(href: merchants_path(base.merge(format: :csv)),  class: DROPDOWN_ITEM) do
            render UI::Icon.new(:file, class: ICON_SM)
            plain "CSV"
          end
          a(href: merchants_path(base.merge(format: :xlsx)), class: DROPDOWN_ITEM) do
            render UI::Icon.new(:file, class: ICON_SM)
            plain "Excel (.xlsx)"
          end
          a(href: merchants_path(base.merge(format: :pdf)),  class: DROPDOWN_ITEM) do
            render UI::Icon.new(:file, class: ICON_SM)
            plain "PDF"
          end
        end
      end
    end

    # ── Table ────────────────────────────────────────────────────────────────────

    def merchants_table
      mtd_volumes = @mtd_volumes
      render UI::Datatable.new(records: @merchants, pagy: @pagy,
                               empty_message: "No merchants registered yet.") do |t|
        t.header { toolbar_content }

        t.column("Business") do |m|
          initials = m.legal_name&.split&.map { |w| w[0] }&.first(2)&.join&.upcase || "??"
          div(class: "flex items-center gap-[10px]") do
            render UI::Avatar.new(initials, size: :sm)
            div do
              p(class: TYPE_BODY_MD) { plain m.legal_name || "—" }
              p(class: TYPE_CAPTION) { plain m.submitted_by_email || "—" }
            end
          end
        end

        t.column("Code") do |m|
          span(class: TYPE_MONO) { plain m.merchant_code || "—" }
        end

        t.column("Country") do |m|
          span(class: TYPE_CAPTION) { plain m.country || "—" }
        end

        t.column("KYB Status") do |m|
          render UI::StatusBadge.new(status: m.status)
        end

        t.column("Volume (MTD)") do |m|
          minor_units = mtd_volumes[m.merchant_code]
          if minor_units.nil? || minor_units == 0
            span(class: TYPE_CAPTION) { plain m.merchant_code.present? ? "GHS 0.00" : "—" }
          else
            span(class: "text-[13px] font-semibold text-gray-800 tabular-nums") do
              plain format_money(minor_units)
            end
          end
        end

        t.column("Applied") do |m|
          span(class: TYPE_CAPTION) { plain m.last_applied_at&.strftime("%d %b %Y") || "—" }
        end

        t.actions do |m|
          a(href: merchant_path(m), class: DROPDOWN_ITEM) do
            render UI::Icon.new(:eye, class: ICON_SM)
            plain "View"
          end
        end
      end
    end
  end
end
