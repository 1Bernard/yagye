# frozen_string_literal: true

module UI
  # Reusable confirm-action modal rendered inside a turbo-frame modal.
  # Use for any destructive or irreversible action that currently uses turbo_confirm.
  #
  # Example controller action:
  #   render UI::ConfirmModal.new(
  #     title:        "Delete role",
  #     body:         "\"#{role.name}\" will be permanently removed.",
  #     confirm_path: team_role_path(role.key),
  #     confirm_method: "delete",
  #     confirm_label: "Delete role",
  #     danger:        true
  #   )
  class ConfirmModal < ApplicationComponent
    include UI::Theme

    def initialize(
      title:,
      body:,
      confirm_path:,
      confirm_method: "post",
      confirm_label: "Confirm",
      danger: false,
      success: false,
      warning_note: nil,
      hidden_fields: {}
    )
      @title          = title
      @body           = body
      @confirm_path   = confirm_path
      @confirm_method = confirm_method
      @confirm_label  = confirm_label
      @btn_class      = danger ? BTN_DANGER : success ? BTN_SUCCESS : BTN_PRIMARY
      @warning_note   = warning_note
      @hidden_fields  = hidden_fields
    end

    def view_template
      turbo_frame(id: "modal-frame") do
        div(class: MODAL_HEAD) do
          h2(class: TEXT_H2) { plain @title }
          button(type: "button", class: XBTN, data: { action: "click->modal#close" }) do
            render UI::Icon.new(:x, class: ICON_SM)
          end
        end

        form(action: @confirm_path, method: "post", data: { turbo_frame: "_top" }) do
          input(type: "hidden", name: "_method", value: @confirm_method) unless @confirm_method == "post"

          div(class: MODAL_BODY) do
            p(class: TYPE_BODY) { plain @body }
            if @warning_note
              div(class: "mt-4 flex items-start gap-2 px-4 py-3 bg-amber-50 border border-amber-200 rounded-xl") do
                span(class: "flex-shrink-0 w-4 h-4 mt-px text-amber-600") do
                  render UI::Icon.new(:alert_circle, class: "w-full h-full")
                end
                p(class: "text-[12.5px] text-amber-800") { plain @warning_note }
              end
            end
          end

          div(class: MODAL_FOOT) do
            input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
            @hidden_fields.each do |name, value|
              input(type: "hidden", name: name.to_s, value: value.to_s)
            end
            button(type: "button", class: BTN_SECONDARY,
                   data: { action: "click->modal#close" }) { plain "Cancel" }
            button(type: "submit", class: @btn_class) { plain @confirm_label }
          end
        end
      end
    end
  end
end
