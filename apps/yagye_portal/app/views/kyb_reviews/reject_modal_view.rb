# frozen_string_literal: true

module KybReviews
  class RejectModalView < ApplicationComponent
    include UI::Theme

    def initialize(application:)
      @app = application
    end

    def view_template
      turbo_frame(id: "modal-frame") do
        div(class: MODAL_HEAD) do
          h2(class: TEXT_H2) { plain "Reject application" }
          button(type: "button", class: XBTN, data: { action: "click->modal#close" }) do
            render UI::Icon.new(:x, class: ICON_SM)
          end
        end
        form(action: reject_kyb_review_path(@app), method: "post") do
          div(class: MODAL_BODY) do
            p(class: "#{TYPE_BODY} mb-4") do
              plain "Provide a reason for rejecting "
              span(class: "font-semibold text-gray-800") { plain @app.legal_name }
              plain ". This will be included in the notification to the merchant."
            end
            label(class: "#{TYPE_LABEL} block mb-1.5", for: "reject_reason") do
              plain "Rejection reason"
            end
            textarea(id: "reject_reason", name: "reason", rows: 4,
                     placeholder: "e.g. Proof of address does not match the business registration address.",
                     required: true,
                     class: "#{TEXTAREA_FIELD} text-[13px]")
          end
          div(class: MODAL_FOOT) do
            input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
            button(type: "button", class: BTN_SECONDARY,
                   data: { action: "click->modal#close" }) { plain "Cancel" }
            button(type: "submit", class: BTN_DANGER) do
              render UI::Icon.new(:alert_circle, class: ICON_SM)
              plain "Confirm rejection"
            end
          end
        end
      end
    end
  end
end
