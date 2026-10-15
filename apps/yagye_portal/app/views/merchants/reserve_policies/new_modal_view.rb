# frozen_string_literal: true

module Merchants
  module ReservePolicies
    class NewModalView < ApplicationComponent
      include UI::Theme

      def initialize(application:)
        @app = application
      end

      def view_template
        turbo_frame(id: "modal-frame") do
          div(class: MODAL_HEAD) do
            div do
              h2(class: TEXT_H2) { plain "Set reserve policy" }
              p(class: "#{TYPE_CAPTION} mt-0.5") { plain @app.legal_name }
            end
            button(type: "button", class: XBTN, data: { action: "click->modal#close" }) do
              render UI::Icon.new(:x, class: ICON_SM)
            end
          end

          form(action: merchant_reserve_policy_path(@app), method: "post") do
            input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)

            div(class: MODAL_BODY) do
              div(class: "flex flex-col gap-4") do
                div do
                  label(class: "#{TEXT_LABEL} block mb-1.5") { plain "Reserve type" }
                  select(name: "kind", id: "reserve_kind", class: SELECT_FIELD) do
                    option(value: "rolling", selected: "selected") { plain "Rolling reserve (% of each settlement)" }
                    option(value: "fixed") { plain "Fixed reserve (set amount per payment)" }
                    option(value: "ad_hoc") { plain "Ad hoc (one-time hold)" }
                  end
                end

                div(id: "reserve_rate_wrap") do
                  label(class: "#{TEXT_LABEL} block mb-1.5") { plain "Reserve rate (%)" }
                  div(class: "relative") do
                    input(type: "number", name: "rate", value: "5", min: "0.01", max: "100",
                          step: "0.01", class: INPUT_FIELD + " pr-8")
                    span(class: "absolute right-3 top-1/2 -translate-y-1/2 text-[12px] text-gray-400") { plain "%" }
                  end
                end

                div(id: "reserve_fixed_wrap", hidden: true) do
                  label(class: "#{TEXT_LABEL} block mb-1.5") { plain "Reserve amount (GHS)" }
                  div(class: "relative") do
                    input(type: "number", name: "fixed_amount", value: "0", min: "0.01",
                          step: "0.01", class: INPUT_FIELD + " pl-14")
                    span(class: "absolute left-3 top-1/2 -translate-y-1/2 text-[12px] text-gray-400") { plain "GHS" }
                  end
                end

                div do
                  label(class: "#{TEXT_LABEL} block mb-1.5") { plain "Hold period (days)" }
                  input(type: "number", name: "hold_days", value: "90", min: "1", max: "365",
                        class: INPUT_FIELD)
                end

                div do
                  label(class: "#{TEXT_LABEL} block mb-1.5") { plain "Mode" }
                  select(name: "mode", class: SELECT_FIELD) do
                    option(value: "live", selected: "selected") { plain "Live" }
                    option(value: "sandbox") { plain "Sandbox" }
                  end
                end

                div do
                  label(class: "#{TEXT_LABEL} block mb-1.5") { plain "Reason for reserve" }
                  textarea(name: "reason", rows: "2",
                           placeholder: "e.g. New merchant onboarding — standard rolling reserve",
                           class: TEXTAREA_FIELD)
                end

                div(class: "bg-amber-50 border border-amber-100 rounded-xl px-4 py-3") do
                  p(class: "text-[11.5px] font-semibold text-amber-800 mb-0.5") { plain "Two-person approval required" }
                  p(class: "text-[11px] text-amber-700") do
                    plain "After a second ops manager approves, the merchant will be notified by email and must acknowledge within 7 days before the reserve activates."
                  end
                end
              end
            end

            script do
            raw <<~JS
              (function() {
                var kind = document.getElementById("reserve_kind");
                var rateW = document.getElementById("reserve_rate_wrap");
                var fixW  = document.getElementById("reserve_fixed_wrap");
                function sync() {
                  rateW.hidden = kind.value !== "rolling";
                  fixW.hidden  = kind.value !== "fixed";
                }
                kind.addEventListener("change", sync);
                sync();
              })();
            JS
          end

          div(class: MODAL_FOOT) do
              button(type: "button", class: BTN_SECONDARY,
                     data: { action: "click->modal#close" }) { plain "Cancel" }
              button(type: "submit", class: BTN_PRIMARY) do
                render UI::Icon.new(:check, class: ICON_SM)
                plain "Create policy"
              end
            end
          end
        end
      end
    end
  end
end
