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
             class: "px-7 py-6 flex flex-col gap-[14px]") do
          input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
          render UI::InputField.new(name: "url", label: "Endpoint URL", type: "url",
                                   placeholder: "https://your-server.com/webhooks", required: true)
          div do
            p(class: "#{TYPE_MICRO} mb-2") { plain "Events to receive" }
            div(class: "flex flex-col gap-1.5") do
              ALL_EVENTS.each do |event|
                label(class: "flex items-center gap-2 cursor-pointer") do
                  input(type: "checkbox", name: "subscribed_events[]", value: event, checked: true,
                        class: "w-[14px] h-[14px] cursor-pointer",
                        style: "accent-color:#{BRAND}")
                  span(class: TYPE_MONO) { plain event }
                end
              end
            end
          end
          div(class: "flex gap-[10px] justify-end mt-1") do
            render UI::Button.new(variant: :secondary, type: "button",
                                  data: { action: "click->drawer#close" }) { plain "Cancel" }
            render UI::Button.new(variant: :primary, type: "submit") do
              render UI::Icon.new(:plus, class: ICON_SM)
              plain "Add endpoint"
            end
          end
        end
      end
    end
  end
end
