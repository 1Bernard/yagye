# frozen_string_literal: true

module Developers
  # Rendered inside the shared drawer-frame turbo frame.
  # Clicking a delivery row on the logs tab loads this.
  class DeliveryDrawerView < ApplicationComponent
    include UI::Theme

    def initialize(delivery:)
      @delivery = delivery
      @endpoint = delivery.portal_webhook_endpoint
    end

    def view_template
      turbo_frame_tag "drawer-frame" do
        drawer_header
        drawer_body
      end
    end

    private

    def drawer_header
      div(class: "flex items-center justify-between px-6 py-5 border-b border-gray-100 sticky top-0 bg-white z-10") do
        div do
          p(class: TYPE_MICRO) { plain "Webhook delivery" }
          p(class: TYPE_TITLE) { plain @delivery.event_type }
        end
        a(href: developers_path(tab: "logs"),
          data: { turbo_frame: "_top" },
          class: XBTN) do
          render UI::Icon.new(:x, class: ICON_SM)
        end
      end
    end

    def drawer_body
      div(class: "p-6 flex flex-col gap-5") do
        summary_card
        request_card
        response_card
      end
    end

    def summary_card
      div(class: "bg-gray-50 border border-gray-100 rounded-2xl px-5 py-[18px]") do
        div(class: "flex items-center gap-[10px] mb-3") do
          render UI::StatusBadge.new(@delivery.state)
          span(class: "#{TYPE_CAPTION} ml-auto") { plain "Attempt #{@delivery.attempt}" }
        end

        detail_row("Endpoint",    @endpoint&.url || "—")
        detail_row("Event ID",    @delivery.short_event_id, mono: true)
        detail_row("HTTP status") { status_pill }
        detail_row("Duration",    @delivery.formatted_duration)
        detail_row("Sent at",     @delivery.last_applied_at.strftime("%d %b %Y, %H:%M:%S UTC"))
      end
    end

    def request_card
      div(class: "#{SURFACE_CARD} overflow-hidden") do
        code_card_header("Request")
        div do
          code_section("Headers", @delivery.formatted_headers)
          div(class: "border-t border-gray-100")
          code_section("Body", @delivery.formatted_request_body)
        end
      end
    end

    def response_card
      div(class: "#{SURFACE_CARD} overflow-hidden") do
        code_card_header("Response")
        code_section("Body", @delivery.response_body.presence || "(empty response)")
      end
    end

    def code_card_header(title)
      div(class: "px-[18px] py-[14px] border-b border-gray-100 bg-gray-50") do
        p(class: TYPE_MICRO) { plain title }
      end
    end

    def code_section(label, content)
      div(class: "px-[18px] py-[14px]") do
        p(class: "#{TYPE_MICRO} mb-2") { plain label }
        pre(class: "#{TYPE_MONO} text-[11.5px] leading-relaxed whitespace-pre-wrap break-all bg-gray-50 border border-gray-100 rounded-[10px] p-3 overflow-x-auto") do
          plain content
        end
      end
    end

    def detail_row(label, value = nil, mono: false)
      div(class: "flex items-center justify-between py-1.5 border-b border-gray-100 last:border-0") do
        span(class: TYPE_CAPTION) { plain label }
        if block_given?
          yield
        else
          span(class: (mono ? TYPE_MONO : TYPE_BODY_MD)) { plain value.to_s }
        end
      end
    end

    def status_pill
      return span(class: TYPE_CAPTION) { plain "—" } unless @delivery.response_status

      cls = @delivery.success? ? "badge-green" : "badge-red"
      span(class: "#{cls} #{BADGE}") { plain @delivery.response_status.to_s }
    end
  end
end
