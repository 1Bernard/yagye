# frozen_string_literal: true

module KybReviews
  class IndexView < ApplicationComponent
    include UI::Theme

    TABS = [
      { key: "pending",   label: "Pending" },
      { key: "in_review", label: "In Review" },
      { key: "approved",  label: "Approved" },
      { key: "rejected",  label: "Rejected" }
    ].freeze

    def initialize(tab: "pending", applications: [], pagy: nil, query: nil,
                   from: nil, to: nil, reviewer: nil, view: "list", stats: {}, mtd_volumes: {})
      @tab          = tab
      @applications = applications
      @pagy         = pagy
      @query        = query
      @from         = from
      @to           = to
      @reviewer     = reviewer
      @view         = view
      @stats        = stats
      @mtd_volumes  = mtd_volumes
    end

    def view_template
      render Layout::Shell.new(
        active_nav: :kyb_reviews,
        title:      "KYB Review",
        breadcrumbs: [ { label: "KYB Review" } ]
      ) do
        render UI::PageHeader.new(title: "KYB Review",
                                  subtitle: "Merchant onboarding applications requiring compliance sign-off.")
        stat_band
        tab_bar
        @view == "grid" ? applications_grid_section : applications_list_section
      end
    end

    private

    def stat_band
      render UI::Grid.new(columns: 4) do
        stat_cell("Pending Review", @stats[:pending].to_s,      icon: :clock,        color: AMBER,  tint: TINT_AMBER)
        stat_cell("In Review",      @stats[:in_review].to_s,    icon: :eye,          color: PURPLE, tint: TINT_PURPLE)
        stat_cell("Approved (30d)", @stats[:approved_30d].to_s, icon: :check_circle, color: GREEN,  tint: TINT_GREEN)
        stat_cell("Rejected (30d)", @stats[:rejected_30d].to_s, icon: :alert_circle, color: RED,    tint: TINT_RED)
      end
    end

    def tab_bar
      render UI::Tabs.new do |t|
        TABS.each do |tab|
          t.tab tab[:label],
                href:   kyb_reviews_path(tab: tab[:key], view: @view),
                active: @tab == tab[:key]
        end
      end
    end

    # ── Toolbar (shared) ─────────────────────────────────────────────────────

    def toolbar_content
      filter_count = [ @from.present?, @to.present?, @reviewer.present? ].count(true)

      form(action: kyb_reviews_path, method: "get",
           data: { controller: "filter-form", filter_form_target: "form" }) do
        input(type: "hidden", name: "tab",  value: @tab)
        input(type: "hidden", name: "view", value: @view)
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
        export_dropdown
        filter_btn(filter_count)
        view_toggle
      end
    end

    def filter_btn(filter_count)
      a(href: filter_kyb_reviews_path(tab: @tab, q: @query, from: @from, to: @to,
                                       reviewer: @reviewer, view: @view),
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

    def export_dropdown
      base = { tab: @tab, q: @query, from: @from, to: @to,
               reviewer: @reviewer, view: @view }.reject { |_, v| v.blank? }

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
          a(href: kyb_reviews_path(base.merge(format: :csv)),  class: DROPDOWN_ITEM) do
            render UI::Icon.new(:file, class: ICON_SM)
            plain "CSV"
          end
          a(href: kyb_reviews_path(base.merge(format: :xlsx)), class: DROPDOWN_ITEM) do
            render UI::Icon.new(:file, class: ICON_SM)
            plain "Excel (.xlsx)"
          end
          a(href: kyb_reviews_path(base.merge(format: :pdf)),  class: DROPDOWN_ITEM) do
            render UI::Icon.new(:file, class: ICON_SM)
            plain "PDF"
          end
        end
      end
    end

    def view_toggle
      base = { tab: @tab, q: @query, from: @from, to: @to,
               reviewer: @reviewer }.reject { |_, v| v.blank? }

      div(class: "flex items-center bg-gray-100 p-[3px] rounded-[10px] gap-[2px]") do
        [ [ :list, "list" ], [ :grid, "grid" ] ].each do |(icon_name, view_val)|
          active = @view == view_val
          attrs  = { href: kyb_reviews_path(base.merge(view: view_val)),
                     class: "flex items-center justify-center w-[30px] h-[30px] rounded-[8px] transition-all" }
          if active
            attrs[:class] += " bg-white text-gray-800"
            attrs[:style]  = "box-shadow:0 1px 3px rgba(0,0,0,0.10),0 1px 2px rgba(0,0,0,0.06)"
          else
            attrs[:class] += " text-gray-400 hover:text-gray-600"
          end
          a(**attrs) { render UI::Icon.new(icon_name, class: "w-[13px] h-[13px]") }
        end
      end
    end

    # ── Grid view ─────────────────────────────────────────────────────────────

    def applications_grid_section
      div(class: "bg-white border border-gray-100 rounded-2xl mb-4") do
        div(class: "flex items-center justify-between px-5 py-3.5") do
          toolbar_content
        end
      end

      if @applications.empty?
        div(class: "flex flex-col items-center justify-center text-center py-16") do
          div(class: "w-12 h-12 rounded-2xl icon-brand flex items-center justify-center mb-3") do
            span(class: "flex w-6 h-6") { render UI::Icon.new(:layers, class: "w-full h-full") }
          end
          p(class: "#{TYPE_BODY_MD} mb-1") { plain "No applications found" }
          p(class: TYPE_CAPTION) { plain empty_message }
        end
      else
        div(class: "grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3") do
          @applications.each { |a| application_grid_card(a) }
        end
        render UI::Pagination.new(pagy: @pagy, class: "mt-4") if @pagy && @pagy.pages > 1
      end
    end

    def application_grid_card(a)
      initials    = a.legal_name&.split&.map { |w| w[0] }&.first(2)&.join&.upcase || "??"
      mtd_units   = @mtd_volumes[a.merchant_code]
      vol_str     = (mtd_units.nil? || mtd_units == 0) ? "GHS 0.00" : format_money(mtd_units)

      a(href: kyb_review_path(a),
        class: "group block bg-white border border-gray-100 rounded-2xl p-5 no-underline #{CARD_HOVER}") do
        div(class: "flex items-start justify-between mb-4") do
          render UI::Avatar.new(initials, size: :lg)
          render UI::StatusBadge.new(status: a.status)
        end

        div(class: "mb-3") do
          p(class: "text-[13.5px] font-semibold text-gray-900 leading-tight tracking-[-0.01em]") do
            plain a.legal_name || "—"
          end
          p(class: "#{TYPE_MONO} mt-[3px]") { plain a.merchant_code || a.application_code }
        end

        div(class: "flex items-center justify-between mb-4") do
          div do
            p(class: "text-[10.5px] text-gray-400 font-medium uppercase tracking-wide") { plain "Volume (MTD)" }
            p(class: "text-[13px] font-semibold text-gray-800 tabular-nums mt-[2px]") { plain vol_str }
          end
          if a.reviewed_by.present?
            div(class: "text-right") do
              p(class: "text-[10.5px] text-gray-400 font-medium uppercase tracking-wide") { plain "Reviewer" }
              p(class: "#{TYPE_CAPTION} mt-[2px] max-w-[100px] truncate") { plain a.reviewed_by }
            end
          else
            span(class: "text-[11px] text-amber-600 font-medium bg-amber-50 px-2 py-[3px] rounded-lg") do
              plain "Unassigned"
            end
          end
        end

        div(class: "flex items-center justify-between pt-3 border-t border-gray-50") do
          p(class: TYPE_CAPTION) { plain "Submitted #{a.last_applied_at&.strftime("%d %b %Y") || "—"}" }
          span(class: "flex w-[13px] h-[13px] text-gray-300 flex-shrink-0 " \
                      "group-hover:text-gray-500 group-hover:translate-x-[2px] transition-all") do
            render UI::Icon.new(:chev_right, class: "w-full h-full")
          end
        end
      end
    end

    # ── List view ─────────────────────────────────────────────────────────────

    def applications_list_section
      offset      = @pagy ? @pagy.offset : 0
      tab         = @tab
      mtd_volumes = @mtd_volumes

      render UI::Datatable.new(records: @applications, pagy: @pagy,
                               empty_message: empty_message) do |t|
        t.header { toolbar_content }

        t.column("#", class: "text-gray-400 tabular-nums text-right w-8") do |_, i|
          plain((offset + i + 1).to_s)
        end

        t.column("Business") do |a|
          div(class: "flex items-center gap-[10px]") do
            render UI::Avatar.new(a.legal_name&.first(2)&.upcase || "??", size: :sm)
            div do
              p(class: TYPE_BODY_MD) { plain a.legal_name || "—" }
              p(class: TYPE_CAPTION) { plain a.merchant_code || a.application_code }
            end
          end
        end

        t.column("Submitted") do |a|
          span(class: TYPE_CAPTION) { plain a.last_applied_at&.strftime("%d %b %Y") || "—" }
        end

        t.column("Reviewer") do |a|
          if a.reviewed_by.present?
            span(class: TYPE_BODY_MD) { plain a.reviewed_by }
          else
            span(class: "text-[11.5px] text-gray-400") { plain "Unassigned" }
          end
        end

        t.column("Volume (MTD)") do |a|
          minor_units = mtd_volumes[a.merchant_code]
          if minor_units.nil? || minor_units == 0
            span(class: TYPE_CAPTION) { plain a.merchant_code.present? ? "GHS 0.00" : "—" }
          else
            span(class: "text-[13px] font-semibold text-gray-800 tabular-nums") do
              plain format_money(minor_units)
            end
          end
        end

        t.column("Status") { |a| render UI::StatusBadge.new(status: a.status) }

        t.actions do |a|
          a(href: kyb_review_path(a), class: DROPDOWN_ITEM) do
            render UI::Icon.new(:eye, class: ICON_SM)
            plain "Review"
          end
          if tab == "pending"
            form(action: assign_kyb_review_path(a), method: "post",
                 style: "display:contents") do
              input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
              button(type: "submit", class: DROPDOWN_ITEM) do
                render UI::Icon.new(:user, class: ICON_SM)
                plain "Assign to me"
              end
            end
          end
        end
      end
    end

    def empty_message
      case @tab
      when "pending"   then "No applications awaiting review."
      when "in_review" then "No applications currently under review."
      when "approved"  then "No approved applications in this window."
      when "rejected"  then "No rejected applications in this window."
      else "No applications found."
      end
    end
  end
end
