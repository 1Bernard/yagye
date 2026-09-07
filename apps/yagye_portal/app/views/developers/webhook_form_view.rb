# frozen_string_literal: true

module Developers
  class WebhookFormView < ApplicationComponent
    include UI::Theme

    ALL_EVENTS = %w[
      payment.paid payment.failed payment.refunded
      dispute.opened dispute.resolved
      merchant.kyb.approved merchant.kyb.rejected
    ].freeze

    def initialize(mode: "test")
      @mode = mode
    end

    def view_template
      turbo_frame_tag "drawer-frame" do
        div(class: DRAWER_HEAD) do
          div do
            p(class: TYPE_TITLE) { plain "Add webhook endpoint" }
            p(class: "#{TYPE_CAPTION} mt-[3px]") { plain "Yagye will POST signed events to this URL." }
          end
          button(type: "button", class: XBTN,
                 data: { action: "click->drawer#close" }) { plain "✕" }
        end

        form(action: developers_webhooks_path, method: "post",
             class: "flex flex-col flex-1 overflow-hidden") do
          input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)

          div(class: "flex-1 overflow-y-auto") do
            # Endpoint URL
            div(class: "px-6 py-5 border-b border-gray-100") do
              section_label("Endpoint URL", :link, "brand")
              div(class: "mt-3") do
                render UI::InputField.new(name: "url", label: nil, type: "url",
                                         placeholder: "https://your-server.com/webhooks",
                                         required: true)
              end
            end

            # Events
            div(class: "px-6 py-5") do
              section_label("Events to receive", :bell, "purple")
              p(class: "#{TYPE_CAPTION} mt-1 mb-3") { plain "Yagye sends a POST request for each selected event." }
              div(class: "flex flex-col gap-1") do
                ALL_EVENTS.each do |event|
                  label(class: "flex items-center gap-3 px-2 py-[8px] rounded-xl hover:bg-gray-50 cursor-pointer transition-colors -mx-2") do
                    input(type: "checkbox", name: "subscribed_events[]", value: event,
                          checked: true,
                          class: "w-[13px] h-[13px] flex-shrink-0 cursor-pointer",
                          style: "accent-color:#{BRAND}")
                    span(class: TYPE_MONO) { plain event }
                  end
                end
              end
            end
          end

          div(class: "flex-shrink-0 flex items-center justify-between px-6 py-4 border-t border-gray-100 bg-white") do
            button(type: "button",
                   class: "text-[12.5px] text-gray-400 hover:text-gray-700 transition-colors",
                   data: { action: "click->drawer#close" }) do
              plain "Cancel"
            end
            button(type: "submit", class: BTN_PRIMARY) do
              render UI::Icon.new(:plus, class: ICON_SM)
              plain "Add endpoint"
            end
          end
        end
      end
    end

    private

    def section_label(label_text, icon, palette)
      div(class: "flex items-center gap-2") do
        div(class: "w-6 h-6 rounded-[7px] flex items-center justify-center flex-shrink-0 icon-#{palette}") do
          span(class: "flex w-[11px] h-[11px]") { render UI::Icon.new(icon, class: "w-full h-full") }
        end
        p(class: "text-[12px] font-semibold text-gray-700") { plain label_text }
      end
    end
  end
end
