# frozen_string_literal: true

module Developers
  class KeyFormView < ApplicationComponent
    include UI::Theme

    SCOPES = [
      { value: "payments:read",  label: "payments:read",  hint: "View payments, transactions and settlement data" },
      { value: "payments:write", label: "payments:write", hint: "Initiate and manage payment requests" },
      { value: "refunds:write",  label: "refunds:write",  hint: "Issue full or partial refunds" },
      { value: "webhooks:write", label: "webhooks:write", hint: "Create and manage webhook endpoints" },
      { value: "customers:read", label: "customers:read", hint: "Read customer and KYC profile data" }
    ].freeze

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
             class: "flex flex-col flex-1 overflow-hidden") do
          input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
          input(type: "hidden", name: "mode", value: @mode)

          div(class: "flex-1 overflow-y-auto") do
            # Key label
            div(class: "px-6 py-5 border-b border-gray-100") do
              section_label("Key label", :edit, "brand")
              div(class: "mt-3") do
                render UI::InputField.new(name: "label", label: nil,
                                         placeholder: "e.g. Production server", required: true)
              end
            end

            # Permissions
            div(class: "px-6 py-5 border-b border-gray-100") do
              section_label("Permissions", :shield, "purple")
              p(class: "#{TYPE_CAPTION} mt-1 mb-3") { plain "Select what this key is allowed to do." }
              div(class: "flex flex-col gap-1") do
                SCOPES.each do |scope|
                  label(class: "flex items-center gap-3 px-2 py-[8px] rounded-xl hover:bg-gray-50 cursor-pointer transition-colors -mx-2") do
                    input(type: "checkbox", name: "scopes[]", value: scope[:value],
                          checked: true,
                          class: "w-[13px] h-[13px] flex-shrink-0 cursor-pointer",
                          style: "accent-color:#{BRAND}")
                    div do
                      span(class: TYPE_MONO) { plain scope[:label] }
                      p(class: TYPE_CAPTION) { plain scope[:hint] }
                    end
                  end
                end
              end
            end

            # Expiry
            div(class: "px-6 py-5") do
              section_label("Expiry", :clock, "brand")
              p(class: "#{TYPE_CAPTION} mt-1 mb-3") { plain "After this period the key will stop working." }
              select(name: "expires_in", class: SELECT_FIELD) do
                option(value: "") { plain "Never expires" }
                option(value: "30")  { plain "30 days" }
                option(value: "90")  { plain "90 days" }
                option(value: "365") { plain "1 year" }
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
              plain "Generate key"
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
