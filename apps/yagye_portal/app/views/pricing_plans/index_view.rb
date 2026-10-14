# frozen_string_literal: true

module PricingPlans
  class IndexView < ApplicationComponent
    include UI::Theme

    STATUS_OPTIONS = [
      ["All statuses", ""],
      ["Draft",        "draft"],
      ["Active",       "active"],
      ["Archived",     "archived"]
    ].freeze

    def initialize(plans: [], query: nil, status_filter: nil)
      @plans         = plans
      @query         = query
      @status_filter = status_filter
    end

    def view_template
      render Layout::Shell.new(
        active_nav:  :pricing_plans,
        title:       "Pricing Plans",
        breadcrumbs: [{ label: "Pricing Plans" }]
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
            rescue
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
    end

    private

    def toolbar
      form(action: pricing_plans_path, method: "get",
           data: { controller: "filter-form", filter_form_target: "form" }) do
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

      div(class: "flex items-center gap-2") do
        status_select
      end
    end

    def status_select
      form(action: pricing_plans_path, method: "get") do
        input(type: "hidden", name: "q", value: @query) if @query.present?
        select(name: "status",
               class: "h-8 border rounded-[9px] pl-3 pr-7 text-[12.5px] font-medium bg-white " \
                      "cursor-pointer appearance-none focus:outline-none transition-colors " \
                      "#{@status_filter.present? ? 'border-gray-400 text-gray-900' : 'border-gray-200 text-gray-600'} " \
                      "hover:border-gray-400",
               onchange: "this.form.submit()") do
          STATUS_OPTIONS.each do |(label, val)|
            if val == @status_filter.to_s
              option(value: val, selected: "selected") { plain label }
            else
              option(value: val) { plain label }
            end
          end
        end
      end
    end

    def empty_message
      if @query.present? || @status_filter.present?
        "No plans match your search."
      else
        "No pricing plans yet. Create one to define the rates merchants are charged."
      end
    end
  end
end
