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
      turbo_frame_tag "drawer-frame", class: "flex flex-col min-h-full w-full" do
        drawer_header
        drawer_body
      end
    end

    private

    def drawer_header
      div(class: "#{DRAWER_HEAD} flex-shrink-0") do
        div(class: "flex items-center gap-3 min-w-0") do
          div(class: "w-8 h-8 rounded-lg icon-brand flex items-center justify-center flex-shrink-0") do
            span(class: "flex w-[14px] h-[14px]") { render UI::Icon.new(:paper_plane, class: "w-full h-full") }
          end
          div(class: "min-w-0") do
            p(class: TYPE_MICRO) { plain "Webhook delivery" }
            p(class: "text-[14px] font-semibold truncate", style: "color:var(--ink)") { plain @delivery.event_type }
          end
        end
        button(type: "button", class: XBTN,
               data: { action: "click->drawer#close" },
               aria: { label: "Close drawer" }) do
          render UI::Icon.new(:x, class: ICON_SM)
        end
      end
    end

    def drawer_body
      div(class: "p-6 pb-20 flex flex-col gap-5") do
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
      div(class: "rounded-2xl overflow-hidden border border-gray-100") do
        dark_card_header("Request")
        dark_code_block("Headers", @delivery.formatted_headers)
        div(class: "h-px bg-[#30363d]")
        dark_code_block("Body", @delivery.formatted_request_body)
      end
    end

    def response_card
      div(class: "rounded-2xl overflow-hidden border border-gray-100") do
        dark_card_header("Response")
        dark_code_block("Body", @delivery.formatted_response_body)
      end
    end

    def dark_card_header(title)
      div(class: "px-[18px] py-[12px] bg-[#161b22] border-b border-[#30363d]") do
        p(class: "text-[10.5px] font-semibold tracking-wider uppercase text-[#8b949e]") { plain title }
      end
    end

    def dark_code_block(label, content)
      div(class: "bg-[#0d1117]") do
        div(class: "flex items-center justify-between px-[18px] py-[10px] border-b border-[#30363d]") do
          span(class: "text-[10px] font-mono font-semibold tracking-wider uppercase text-[#8b949e]") { plain label }
          button(type: "button",
                 class: "flex items-center gap-[4px] text-[10.5px] text-[#8b949e] hover:text-[#c9d1d9] transition-colors cursor-pointer bg-transparent border-0",
                 data: { controller: "clipboard", clipboard_text_value: content, action: "click->clipboard#copy" }) do
            render UI::Icon.new(:copy, class: "w-[10px] h-[10px]")
            span(data: { clipboard_target: "label" }) { plain "Copy" }
          end
        end
        div(class: "px-[18px] py-[14px] overflow-x-auto") do
          pre(class: "text-[11.5px] leading-[1.7] font-mono m-0 whitespace-pre text-[#c9d1d9]",
              data: { controller: "json-highlight" }) { plain content }
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

      cls = @delivery.success? ? STATUS_SUCCESS : STATUS_FAILED
      span(class: "#{BADGE} #{cls}") { plain @delivery.response_status.to_s }
    end
  end
end
