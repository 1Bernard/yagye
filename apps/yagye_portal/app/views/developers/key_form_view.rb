# frozen_string_literal: true

module Developers
  class KeyFormView < ApplicationComponent
    include UI::Theme

    def initialize(mode: "test")
      @mode = mode
    end

    def view_template
      turbo_frame_tag "drawer-frame" do
        div(class: DRAWER_HEAD) do
          div do
            p(class: TYPE_TITLE) { plain "Generate API key" }
            p(class: "#{TYPE_CAPTION} mt-[3px]") { plain "Keys are shown once. Store it immediately after creation." }
          end
          button(type: "button", class: XBTN,
                 data: { action: "click->drawer#close" }) { plain "✕" }
        end

        form(action: developers_keys_path, method: "post",
             class: "px-7 py-6 flex flex-col gap-[14px]") do
          input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
          input(type: "hidden", name: "mode", value: @mode)
          render UI::InputField.new(name: "label", label: "Key label",
                                   placeholder: "e.g. Production server", required: true)
          div(class: "flex gap-[10px] justify-end mt-1") do
            render UI::Button.new(variant: :secondary, type: "button",
                                  data: { action: "click->drawer#close" }) { plain "Cancel" }
            render UI::Button.new(variant: :primary, type: "submit") do
              render UI::Icon.new(:plus, class: ICON_SM)
              plain "Generate"
            end
          end
        end
      end
    end
  end
end
