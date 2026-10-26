# frozen_string_literal: true

module Payments
  class RefundModalView < ApplicationComponent
    include UI::Theme

    def initialize(payment:)
      @payment = payment
    end

    def view_template
      turbo_frame(id: "modal-frame") do
        div(class: MODAL_HEAD) do
          div do
            h2(class: TEXT_H2) { plain "Issue refund" }
            p(class: "#{TYPE_CAPTION} mt-0.5") do
              plain "Refund up to #{@payment.formatted_amount} to the original payment method."
            end
          end
          button(type: "button", class: XBTN, data: { action: "click->modal#close" }) do
            render UI::Icon.new(:x, class: ICON_SM)
          end
        end

        form(action: payment_refund_path(@payment), method: "post",
             data: { turbo_frame: "_top" }) do
          div(class: MODAL_BODY) do
            div(class: "flex flex-col gap-4") do
              div do
                label(class: "#{TEXT_LABEL} block mb-1.5", for: "refund_amount") { plain "Refund amount (GHS)" }
                input(id: "refund_amount", type: "number", name: "amount",
                      value: "%.2f" % (@payment.amount / 100.0),
                      min: "0.01",
                      max: "%.2f" % (@payment.amount / 100.0),
                      step: "0.01",
                      class: INPUT_FIELD)
                p(class: "#{TYPE_CAPTION} mt-1.5") { plain "Maximum: #{@payment.formatted_amount}." }
              end

              div do
                label(class: "#{TEXT_LABEL} block mb-1.5", for: "refund_reason") { plain "Reason" }
                select(id: "refund_reason", name: "reason", class: SELECT_FIELD) do
                  option(value: "requested_by_merchant") { plain "Requested by merchant" }
                  option(value: "duplicate")             { plain "Duplicate charge" }
                  option(value: "fraudulent")            { plain "Fraudulent transaction" }
                  option(value: "customer_request")      { plain "Customer request" }
                end
              end
            end
          end

          div(class: MODAL_FOOT) do
            input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
            button(type: "button", class: BTN_SECONDARY,
                   data: { action: "click->modal#close" }) { plain "Cancel" }
            button(type: "submit", class: BTN_DANGER) do
              render UI::Icon.new(:refresh, class: ICON_SM)
              plain "Confirm refund"
            end
          end
        end
      end
    end
  end
end
