# frozen_string_literal: true

module PricingPlans
  class IndexView < ApplicationComponent
    include UI::Theme

    TABS = [
      { key: "all",      label: "All"      },
      { key: "draft",    label: "Draft"    },
      { key: "active",   label: "Active"   },
      { key: "archived", label: "Archived" }
    ].freeze

    def initialize(plans: [], tab: "all", query: nil, stats: {})
      @plans = plans
      @tab   = tab
      @query = query
      @stats = stats
    end

    def view_template
      render Layout::Shell.new(
        active_nav:  :pricing_plans,
        title:       "Pricing Plans",
        breadcrumbs: [ { label: "Pricing Plans" } ]
      ) do
        render UI::PageHeader.new(
          title:    "Pricing Plans",
          subtitle: "Global rate plans assigned to merchants at transaction time."
        ) do
          render UI::Button.new(variant: :primary, href: new_pricing_plan_path) do
            render UI::Icon.new(:plus, class: "w-[14px] h-[14px]")
            plain "New plan"
          end
        end

        stat_band
        tab_bar
        plans_table
      end
    end

    private

    def stat_band
      render UI::Grid.new(columns: 4) do
        stat_cell("Total plans",   @stats[:total].to_s,    icon: :tag,          color: BRAND,  tint: TINT_BRAND)
        stat_cell("Active",        @stats[:active].to_s,   icon: :check_circle, color: GREEN,  tint: TINT_GREEN)
        stat_cell("Draft",         @stats[:draft].to_s,    icon: :clock,        color: AMBER,  tint: TINT_AMBER)
        stat_cell("Archived",      @stats[:archived].to_s, icon: :archive,      color: PURPLE, tint: TINT_PURPLE)
      end
    end

    def tab_bar
      render UI::Tabs.new do |t|
        TABS.each do |tab|
          t.tab tab[:label],
                href:   pricing_plans_path(tab: tab[:key]),
                active: @tab == tab[:key]
        end
      end
    end

    def plans_table
      render UI::Datatable.new(
        records:       @plans,
        empty_message: empty_message,
        empty_icon:    :tag
      ) do |t|
        t.header { toolbar }

        t.column("Plan") do |p|
          div do
            span(class: TYPE_BODY_MD) { plain p["name"] || "—" }
            span(class: "block #{TYPE_MONO} text-gray-400 mt-px") { plain "v#{p["version"]}" } if p["version"]
          end
        end

        t.column("Status") do |p|
          render UI::StatusBadge.new(status: p["status"] || "draft")
        end

        t.column("Currency") { |p| plain(p["currency"] || "—") }

        t.column("Fee mode") do |p|
          mode = p["fee_mode"] == "invoiced" ? "Invoiced" : "Deducted"
          span(class: "#{BADGE} #{p["fee_mode"] == 'invoiced' ? STATUS_INFO : STATUS_SUCCESS}") { plain mode }
        end

        t.column("Monthly fee", class: "text-right tabular-nums") do |p|
          cur     = p["currency"] || "GHS"
          monthly = p["monthly_fee"].to_i
          plain(monthly.positive? ? format_money(monthly, currency: cur) : "—")
        end

        t.column("Active from") do |p|
          eff = begin
            fmt_date(Date.parse(p["effective_from"].to_s)) if p["effective_from"]
          rescue ArgumentError, TypeError
            nil
          end
          plain(eff || "—")
        end

        t.column("Created by") { |p| plain(p["created_by"] || "—") }

        t.actions do |p|
          a(href: pricing_plan_path(p["id"]), class: DROPDOWN_ITEM) do
            render UI::Icon.new(:eye, class: ICON_SM)
            plain "View"
          end
        end
      end
    end

    def toolbar
      form(action: pricing_plans_path, method: "get",
           data: { controller: "filter-form", filter_form_target: "form" }) do
        input(type: "hidden", name: "tab", value: @tab)
        div(class: FILTER_SEARCH_WRAP) do
          span(class: "flex w-[13px] h-[13px] text-gray-400 flex-shrink-0") do
            render UI::Icon.new(:search, class: "w-full h-full")
          end
          input(type: "search", name: "q", value: @query,
                placeholder: "Search by name…",
                class: FILTER_SEARCH_INPUT,
                data: { action: "input->filter-form#submit" })
        end
      end
    end

    def empty_message
      case @tab
      when "draft"    then "No draft plans."
      when "active"   then "No active plans yet. Activate a draft plan to make it assignable."
      when "archived" then "No archived plans."
      else
        @query.present? ? "No plans match your search." : "No pricing plans yet."
      end
    end
  end
end
