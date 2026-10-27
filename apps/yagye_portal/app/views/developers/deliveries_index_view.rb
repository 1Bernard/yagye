# frozen_string_literal: true

module Developers
  class DeliveriesIndexView < ApplicationComponent
    include UI::Theme

    def initialize(deliveries:, pagy:)
      @deliveries = deliveries
      @pagy       = pagy
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
          t.column("Merchant") do |d|
            span(class: TYPE_MONO) { plain d.merchant_code || "—" }
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
  end
end
