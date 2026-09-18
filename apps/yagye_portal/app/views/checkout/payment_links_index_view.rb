# frozen_string_literal: true

module Checkout
  class PaymentLinksIndexView < ApplicationComponent
    include UI::Theme

    CURRENCY_SYMBOLS = { "GHS" => "GH₵", "USD" => "$", "EUR" => "€", "GBP" => "£", "NGN" => "₦" }.freeze

    def initialize(links:, query: nil, view: "list", active_filter: nil)
      @links         = links
      @query         = query
      @view          = view
      @active_filter = active_filter
    end

    def view_template
      render Layout::Shell.new(
        active_nav: :payment_links,
        title: "Payment Links",
        breadcrumbs: [ { label: "Payment Links" } ]
      ) do
        render UI::PageHeader.new(
          title:    "Payment links",
          subtitle: "Create shareable links that take customers straight to checkout."
        ) do
          render UI::Button.new(variant: :primary, href: new_payment_link_path) do
            render UI::Icon.new(:plus, class: ICON_SM)
            plain "New link"
          end
        end

        if @links.empty? && @query.blank? && @active_filter.blank?
          empty_state
        elsif @view == "grid"
          links_grid_section
        else
          links_list_section
        end
      end
    end

    private

    # ── Toolbar ───────────────────────────────────────────────────────────────

    def toolbar_content
      filter_count = [ @active_filter.present? ].count(true)

      form(action: payment_links_path, method: "get",
           data: { controller: "filter-form", filter_form_target: "form" }) do
        input(type: "hidden", name: "view", value: @view)
        div(class: FILTER_SEARCH_WRAP) do
          span(class: "flex w-[13px] h-[13px] text-gray-400 flex-shrink-0") do
            render UI::Icon.new(:search, class: "w-full h-full")
          end
          input(type: "search", name: "q", value: @query,
                placeholder: "Search by description or slug…",
                class: FILTER_SEARCH_INPUT)
        end
      end

      div(class: "flex items-center gap-2") do
        filter_btn(filter_count)
        view_toggle
      end
    end

    def filter_btn(filter_count)
      a(href: filter_payment_links_path(q: @query, active: @active_filter, view: @view),
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

    def view_toggle
      base = { q: @query, active: @active_filter }.reject { |_, v| v.blank? }

      div(class: "flex items-center bg-gray-100 p-[3px] rounded-[10px] gap-[2px]") do
        [ [ :list, "list" ], [ :grid, "grid" ] ].each do |(icon_name, view_val)|
          active = @view == view_val
          attrs  = { href: payment_links_path(base.merge(view: view_val)),
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

    def links_grid_section
      div(class: "bg-white border border-gray-100 rounded-2xl mb-4") do
        div(class: "flex items-center justify-between px-5 py-3.5") do
          toolbar_content
        end
      end

      if @links.empty?
        div(class: "flex flex-col items-center justify-center text-center py-16") do
          div(class: "w-12 h-12 rounded-2xl icon-brand flex items-center justify-center mb-3") do
            span(class: "flex w-6 h-6") { render UI::Icon.new(:link, class: "w-full h-full") }
          end
          p(class: "#{TYPE_BODY_MD} mb-1") { plain "No payment links found" }
          p(class: TYPE_CAPTION) { plain "Try a different search or filter." }
        end
      else
        div(class: "grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3") do
          @links.each { |link| link_grid_card(link) }
        end
      end
    end

    def link_grid_card(link)
      a(href: payment_link_layout_path(link["id"]),
        class: "group block bg-white border border-gray-100 rounded-2xl p-5 no-underline #{CARD_HOVER}") do
        div(class: "flex items-start justify-between mb-4") do
          div(class: "w-10 h-10 rounded-xl icon-brand flex items-center justify-center flex-shrink-0") do
            span(class: "flex w-5 h-5") { render UI::Icon.new(:link, class: "w-full h-full") }
          end
          badge = link["active"] ? BADGE_SUCCESS : BADGE_NEUTRAL
          span(class: badge) { plain link["active"] ? "Active" : "Inactive" }
        end

        div(class: "mb-3") do
          p(class: "text-[13.5px] font-semibold text-gray-900 leading-tight tracking-[-0.01em]") do
            plain link["description"] || "Untitled link"
          end
          p(class: "#{TYPE_CAPTION} mt-[3px]") { plain link["url_slug"] }
        end

        div(class: "mb-4") do
          if link["amount"]
            sym = CURRENCY_SYMBOLS.fetch(link["currency"].to_s, link["currency"].to_s)
            p(class: "text-[15px] font-semibold text-gray-900 tabular-nums") do
              plain "#{sym}#{"%.2f" % (link["amount"] / 100.0)}"
            end
          else
            p(class: TYPE_CAPTION) { plain "Customer sets amount" }
          end
        end

        div(class: "flex items-center justify-between pt-3 border-t border-gray-50") do
          uses = link["use_count"] || 0
          max  = link["max_uses"]
          p(class: TYPE_CAPTION) { plain max ? "#{uses} / #{max} uses" : "#{uses} use#{"s" if uses != 1}" }
          span(class: "flex w-[13px] h-[13px] text-gray-300 flex-shrink-0 " \
                      "group-hover:text-gray-500 group-hover:translate-x-[2px] transition-all") do
            render UI::Icon.new(:chev_right, class: "w-full h-full")
          end
        end
      end
    end

    # ── List view ─────────────────────────────────────────────────────────────

    def links_list_section
      render UI::Datatable.new(records: @links, empty_message: "No payment links found.") do |t|
        t.header { toolbar_content }

        t.column("#", class: "text-gray-400 tabular-nums text-right w-8") do |_, i|
          plain((i + 1).to_s)
        end
        t.column("Description") do |link|
          div(class: "flex flex-col gap-0.5") do
            span(class: TYPE_BODY_MD) { plain link["description"] || "—" }
            span(class: TYPE_MONO)   { plain link["url_slug"] }
          end
        end
        t.column("Amount", class: "text-right tabular-nums") do |link|
          if link["amount"]
            sym = CURRENCY_SYMBOLS.fetch(link["currency"].to_s, link["currency"].to_s)
            plain "#{sym}#{"%.2f" % (link["amount"] / 100.0)}"
          else
            span(class: TYPE_CAPTION) { plain "Customer sets amount" }
          end
        end
        t.column("Status") do |link|
          badge = link["active"] ? BADGE_SUCCESS : BADGE_NEUTRAL
          span(class: badge) { plain link["active"] ? "Active" : "Inactive" }
        end
        t.column("Uses", class: "text-right tabular-nums") do |link|
          uses = link["use_count"] || 0
          max  = link["max_uses"]
          plain max ? "#{uses} / #{max}" : uses.to_s
        end

        t.actions do |link|
          a(href: payment_link_layout_path(link["id"]), class: DROPDOWN_ITEM) do
            render UI::Icon.new(:edit, class: ICON_SM)
            plain "Edit layout"
          end
        end
      end
    end

    # ── Empty state (no links at all) ─────────────────────────────────────────

    def empty_state
      div(class: "#{SURFACE_CARD} flex flex-col items-center justify-center py-20 gap-4") do
        div(class: "w-14 h-14 rounded-2xl bg-gray-100 flex items-center justify-center") do
          span(class: "w-6 h-6 text-gray-400") { render UI::Icon.new(:link, class: "w-full h-full") }
        end
        div(class: "text-center") do
          p(class: TYPE_TITLE) { plain "No payment links yet" }
          p(class: "#{TYPE_CAPTION} mt-1 max-w-xs") do
            plain "Create a link to start accepting payments without any integration."
          end
        end
        render UI::Button.new(variant: :primary, href: new_payment_link_path) do
          render UI::Icon.new(:plus, class: ICON_SM)
          plain "Create payment link"
        end
      end
    end
  end
end
