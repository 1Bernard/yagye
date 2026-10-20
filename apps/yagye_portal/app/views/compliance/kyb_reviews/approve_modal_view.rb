# frozen_string_literal: true

module Compliance
  module KybReviews
  class ApproveModalView < ApplicationComponent
    include UI::Theme

    def initialize(application:)
      @app = application
    end

    def view_template
      turbo_frame(id: "modal-frame") do
        div(class: MODAL_HEAD) do
          h2(class: TEXT_H2) { plain "Approve application" }
          button(type: "button", class: XBTN, data: { action: "click->modal#close" }) do
            render UI::Icon.new(:x, class: ICON_SM)
          end
        end

        form(action: approve_kyb_review_path(@app), method: "post") do
          div(class: MODAL_BODY) do
            p(class: TYPE_BODY) do
              plain "You are about to approve "
              span(class: "font-semibold text-gray-800") { plain @app.legal_name }
              plain ". The merchant will be notified immediately and their account will be activated."
            end
            div(class: "mt-4 flex items-start gap-2 px-4 py-3 bg-green-50 border border-green-200 rounded-xl") do
              span(class: "flex-shrink-0 w-4 h-4 mt-px text-green-600") do
                render UI::Icon.new(:check_circle, class: "w-full h-full")
              end
              p(class: "text-[12.5px] text-green-800") do
                plain "This action cannot be undone. Make sure all documents and KYB checks have been reviewed."
              end
            end
          end

          div(class: MODAL_FOOT) do
            input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
            button(type: "button", class: BTN_SECONDARY,
                   data: { action: "click->modal#close" }) { plain "Cancel" }
            button(type: "submit", class: BTN_SUCCESS) do
              render UI::Icon.new(:check_circle, class: ICON_SM)
              plain "Confirm approval"
            end
          end
        end
      end
    end
  end
  end
end
