# frozen_string_literal: true

module Developers
  class DeliveriesIndexView < ApplicationComponent
    include UI::Theme

    def initialize(deliveries:, pagy:, state: nil, event_type: nil, from: nil, to: nil)
      @deliveries = deliveries
      @pagy       = pagy
      @state      = state
      @event_type = event_type
      @from       = from
      @to         = to
    end

    def view_template
      render Layout::Shell.new(
        active_nav:  :webhook_deliveries,
        title:       "Webhook Deliveries",
        breadcrumbs: [ { label: "Webhook Deliveries" } ]
      ) do
        render UI::PageHeader.new(
          title:    "Webhook Deliveries",
          subtitle: "All outbound delivery attempts across merchants. Last 30 days."
        )

        render UI::Datatable.new(
          records:       @deliveries,
          pagy:          @pagy,
          empty_message: "No webhook delivery attempts in the last 30 days."
        ) do |t|
          t.header { toolbar_content }

          t.column("Merchant") do |d|
            name = d.portal_merchant&.trading_name
            if name.present?
              div do
                span(class: "text-[13px] font-medium text-gray-800") { plain name }
                span(class: "block text-[11px] text-gray-400 font-mono mt-px") { plain d.merchant_code }
              end
            else
              span(class: TYPE_MONO) { plain d.merchant_code || "—" }
            end
          end

          t.column("Event") do |d|
            div do
              p(class: TYPE_BODY_MD) { plain d.event_type }
              p(class: TYPE_CAPTION) { plain d.short_event_id }
            end
          end

          t.column("Endpoint") do |d|
            code(class: "#{TYPE_MONO} text-[11px] truncate max-w-[200px] block") do
              plain(d.portal_webhook_endpoint&.url || "—")
            end
          end

          t.column("Status") { |d| render UI::StatusBadge.new(status: d.state) }

          t.column("HTTP") do |d|
            if d.response_status
              color = d.response_status.between?(200, 299) ? "#16a34a" : "#dc2626"
              bg    = d.response_status.between?(200, 299) ? "#f0fdf4" : "#fef2f2"
              span(class: "text-[11.5px] font-semibold px-2 py-[2px] rounded-full font-mono",
                   style: "color:#{color};background:#{bg}") { plain d.response_status.to_s }
            else
              span(class: TYPE_CAPTION) { plain "—" }
            end
          end

          t.column("Duration") { |d| span(class: TYPE_CAPTION) { plain d.formatted_duration } }
          t.column("Attempt")  { |d| span(class: TYPE_CAPTION) { plain d.attempt.to_s } }
          t.column("Sent")     { |d| span(class: TYPE_CAPTION) { plain fmt_datetime(d.last_applied_at) } }

          t.actions do |d|
            a(href: developers_delivery_path(d),
              class: DROPDOWN_ITEM,
              data:  { turbo_frame: "drawer-frame" }) do
              render UI::Icon.new(:eye, class: ICON_SM)
              plain "Inspect"
            end
          end
        end
      end
    end

    private

    def toolbar_content
      filter_count = [ @state.presence, @event_type.presence,
                       (@from.presence || @to.presence) ].compact.count

      form(action: developers_deliveries_path, method: "get",
           data: { controller: "filter-form", filter_form_target: "form" }) do
        div(class: FILTER_SEARCH_WRAP) do
          span(class: "flex w-[13px] h-[13px] text-gray-400 flex-shrink-0") do
            render UI::Icon.new(:search, class: "w-full h-full")
          end
          input(type: "search", name: "event_type", value: @event_type,
                placeholder: "Search by event type…",
                class: FILTER_SEARCH_INPUT)
        end
      end

      a(href: filter_developers_deliveries_path(state: @state, event_type: @event_type,
                                                from: @from, to: @to),
        class: "inline-flex items-center gap-[5px] px-3 h-8 border rounded-[9px] " \
               "text-[12.5px] font-medium bg-white cursor-pointer transition-colors no-underline " \
               "#{filter_count > 0 ? 'border-gray-400 text-gray-900' : 'border-gray-200 text-gray-600'} " \
               "hover:border-gray-400",
        data: { turbo_frame: "drawer-frame" }) do
        render UI::Icon.new(:filter, class: "w-3 h-3")
        plain "Filters"
        if filter_count > 0
          span(class: "ml-[2px] inline-flex items-center justify-center w-4 h-4 rounded-full " \
                      "text-white text-[9px] font-bold leading-none",
               style: "background:#{BRAND}") do
            plain filter_count.to_s
          end
        end
      end
    end
  end
end
