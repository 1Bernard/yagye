# frozen_string_literal: true

module Developers
  # Rendered inside the shared drawer-frame turbo frame.
  # Clicking a delivery row on the logs tab loads this.
  class DeliveryDrawerPage < ApplicationComponent
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
      div(style: "display:flex;align-items:center;justify-content:space-between;" \
                 "padding:20px 24px;border-bottom:1px solid #{BORDER};position:sticky;" \
                 "top:0;background:#fff;z-index:10") do
        div do
          p(style: TYPE_MICRO) { "Webhook delivery" }
          p(style: TYPE_TITLE) { @delivery.event_type }
        end
        a(href: developers_path(tab: "logs"),
          data: { turbo_frame: "_top" },
          class: XBTN) do
          render UI::Icon.new(:x, class: ICON_SM)
        end
      end
    end

    def drawer_body
      div(style: "padding:24px;display:flex;flex-direction:column;gap:20px") do
        summary_card
        request_card
        response_card
      end
    end

    def summary_card
      div(style: "background:#{SURFACE};border:1px solid #{BORDER};border-radius:16px;padding:18px 20px") do
        div(style: "display:flex;align-items:center;gap:10px;margin-bottom:12px") do
          div(style: "width:10px;height:10px;border-radius:50%;background:#{@delivery.state_color};flex-shrink:0")
          span(style: "font-size:12.5px;font-weight:600;color:#{@delivery.state_color}") do
            @delivery.state.capitalize
          end
          span(style: "#{TYPE_CAPTION};margin-left:auto") do
            "Attempt #{@delivery.attempt}"
          end
        end

        detail_row("Endpoint", @endpoint&.url || "—")
        detail_row("Event ID", @delivery.short_event_id, mono: true)
        detail_row("HTTP status", status_pill)
        detail_row("Duration", @delivery.formatted_duration)
        detail_row("Sent at", @delivery.last_applied_at.strftime("%d %b %Y, %H:%M:%S UTC"))
      end
    end

    def request_card
      div(style: "background:#fff;border:1px solid #{BORDER};border-radius:16px;overflow:hidden") do
        code_card_header("Request")
        div(style: "display:flex;flex-direction:column;gap:0") do
          code_section("Headers", @delivery.formatted_headers)
          div(style: "border-top:1px solid #{BORDER}")
          code_section("Body", @delivery.formatted_request_body)
        end
      end
    end

    def response_card
      div(style: "background:#fff;border:1px solid #{BORDER};border-radius:16px;overflow:hidden") do
        code_card_header("Response")
        code_section("Body", @delivery.response_body.presence || "(empty response)")
      end
    end

    def code_card_header(title)
      div(style: "padding:14px 18px;border-bottom:1px solid #{BORDER};background:#{SURFACE}") do
        p(style: TYPE_MICRO) { title }
      end
    end

    def code_section(label, content)
      div(style: "padding:14px 18px") do
        p(style: "#{TYPE_MICRO};margin-bottom:8px") { label }
        pre(style: "#{TYPE_MONO};font-size:11.5px;line-height:1.6;white-space:pre-wrap;" \
                   "word-break:break-all;background:#{SURFACE};border:1px solid #{BORDER};" \
                   "border-radius:10px;padding:12px;overflow-x:auto") do
          plain content
        end
      end
    end

    def detail_row(label, value_or_content = nil, mono: false)
      div(style: "display:flex;align-items:center;justify-content:space-between;" \
                 "padding:6px 0;border-bottom:1px solid #{BORDER};last-child:border-0") do
        span(style: TYPE_CAPTION) { label }
        if block_given?
          yield
        else
          span(style: mono ? TYPE_MONO : TYPE_BODY_MD) { value_or_content }
        end
      end
    end

    def status_pill
      return span(style: TYPE_CAPTION) { "—" } unless @delivery.response_status

      color = @delivery.success? ? "#16a34a" : "#dc2626"
      bg    = @delivery.success? ? "#f0fdf4" : "#fef2f2"

      span(style: "font-size:12px;font-weight:600;color:#{color};background:#{bg};" \
                  "padding:2px 9px;border-radius:16px") do
        @delivery.response_status.to_s
      end
    end
  end
end
