# frozen_string_literal: true

module Compliance
  module Approvals
    class RejectModalView < ApplicationComponent
      include UI::Theme

      def initialize(record:)
        @record = record
      end

      def view_template
        turbo_frame(id: "modal-frame") do
          div(class: MODAL_HEAD) do
            h2(class: TEXT_H2) { plain "Reject adjustment" }
            button(type: "button", class: XBTN, data: { action: "click->modal#close" }) do
              render UI::Icon.new(:x, class: ICON_SM)
            end
          end

          form(action: compliance_reject_approval_path(@record), method: "post") do
            input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)

            div(class: MODAL_BODY) do
              p(class: "#{TYPE_BODY} text-gray-600 mb-5") do
                plain "Provide a reason for rejecting this adjustment. It is recorded for the audit trail."
              end
              label(class: "block #{TYPE_MICRO} text-gray-500 font-medium mb-1.5") { plain "Reason" }
              textarea(name: "reason", rows: 3, required: true,
                       placeholder: "Explain why this adjustment is being rejected…",
                       class: "#{TEXTAREA_FIELD} placeholder:text-gray-400")
            end

            div(class: MODAL_FOOT) do
              button(type: "button", class: BTN_SECONDARY,
                     data: { action: "click->modal#close" }) { plain "Cancel" }
              button(type: "submit", class: BTN_DANGER) do
                render UI::Icon.new(:x, class: ICON_SM)
                plain "Confirm rejection"
              end
            end
          end
        end
      end
    end
  end
end
