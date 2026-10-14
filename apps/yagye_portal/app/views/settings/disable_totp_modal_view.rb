# frozen_string_literal: true

module Settings
  class DisableTotpModalView < ApplicationComponent
    include UI::Theme

    def view_template
      turbo_frame(id: "modal-frame") do
        div(class: MODAL_HEAD) do
          h2(class: TEXT_H2) { plain "Disable two-factor authentication" }
          button(type: "button", class: XBTN, data: { action: "click->modal#close" }) do
            render UI::Icon.new(:x, class: ICON_SM)
          end
        end

        form(action: settings_totp_delete_path, method: "post") do
          input(type: "hidden", name: "_method",            value: "delete")
          input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)

          div(class: MODAL_BODY) do
            div(class: "flex items-start gap-3 px-4 py-3 bg-amber-50 border border-amber-200 rounded-xl mb-5") do
              span(class: "flex-shrink-0 w-4 h-4 mt-px text-amber-600") do
                render UI::Icon.new(:alert_circle, class: "w-full h-full")
              end
              p(class: "text-[12.5px] text-amber-800") do
                plain "Removing 2FA makes your account less secure. You will only be protected by your email and password."
              end
            end
            render UI::InputField.new(
              name:         "current_password",
              label:        "Current password",
              type:         "password",
              autocomplete: "current-password"
            )
          end

          div(class: MODAL_FOOT) do
            button(type: "button", class: BTN_SECONDARY,
                   data: { action: "click->modal#close" }) { plain "Cancel" }
            button(type: "submit", class: BTN_DANGER) do
              render UI::Icon.new(:shield_off, class: ICON_SM)
              plain "Disable 2FA"
            end
          end
        end
      end
    end
  end
end
