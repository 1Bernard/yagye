# frozen_string_literal: true

module Developers
  class ProviderFormView < ApplicationComponent
    include UI::Theme

    METHODS = [
      { value: "mobile_money",  label: "Mobile Money (MoMo)" },
      { value: "card",          label: "Card payments" },
      { value: "bank_transfer", label: "Bank transfer" }
    ].freeze

    FIELD_LABEL = "text-[12px] font-semibold text-gray-700 leading-tight"

    def initialize(connection:, psps:, mode:, error: nil)
      @connection = connection
      @psps       = psps
      @mode       = mode
      @error      = error
    end

    def view_template
      title   = @mode == :new ? "Connect a PSP" : "Edit provider connection"
      subtitle =
        if @mode == :new
          "Connect an external PSP to enable multi-PSP routing for your account."
        else
          "Update the priority, status, or enabled payment methods for this connection."
        end

      turbo_frame_tag "drawer-frame" do
        div(class: DRAWER_HEAD) do
          div do
            p(class: TYPE_TITLE) { plain title }
            p(class: "#{TYPE_CAPTION} mt-[3px]") { plain subtitle }
          end
          button(type: "button", class: XBTN,
                 data: { action: "click->drawer#close" }) { plain "✕" }
        end

        if @error
          div(class: "px-5 pb-3") do
            render UI::Notice.new(variant: :error, body: @error)
          end
        end

        form(
          action: form_action,
          method: "post",
          data:   { turbo_frame: "_top" },
          class:  "flex flex-col gap-5 px-5 pb-6"
        ) do
          input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
          input(type: "hidden", name: "_method", value: "patch") if @mode == :edit

          if @mode == :new
            psp_selector_field
            mode_field
          end

          priority_field
          enabled_methods_field
          credentials_section if @mode == :new

          div(class: "flex gap-3 pt-2") do
            button(type: "submit", class: "#{BTN_PRIMARY} flex-1 justify-center") do
              plain @mode == :new ? "Connect provider" : "Save changes"
            end
            a(href: developers_providers_path,
              class: "#{BTN_SECONDARY} flex-1 justify-center text-center") do
              plain "Cancel"
            end
          end
        end
      end
    end

    private

    def form_action
      @mode == :new ? developers_providers_create_path : developers_provider_path(@connection["id"])
    end

    def psp_selector_field
      div(class: "flex flex-col gap-1") do
        label(for: "provider_code", class: FIELD_LABEL) { plain "Provider" }
        select(name: "provider_code", id: "provider_code", class: SELECT_FIELD) do
          option(value: "", disabled: true, selected: true) { plain "Select a PSP…" }
          @psps.each do |psp|
            option(value: psp[:code]) { plain psp[:label] }
          end
        end
        p(class: FORM_HINT) { plain "Choose the external PSP to connect to your account." }
      end
    end

    def mode_field
      div(class: "flex flex-col gap-1") do
        label(for: "mode", class: FIELD_LABEL) { plain "Mode" }
        select(name: "mode", id: "mode", class: SELECT_FIELD) do
          option(value: "sandbox") { plain "Sandbox (test)" }
          option(value: "live")    { plain "Live (production)" }
        end
        p(class: FORM_HINT) { plain "Use sandbox to test routing before going live." }
      end
    end

    def priority_field
      current = @connection ? @connection["priority"].to_i : 1
      div(class: "flex flex-col gap-1") do
        label(for: "priority", class: FIELD_LABEL) { plain "Priority" }
        input(type: "number", name: "priority", id: "priority",
              value: current, min: 1, max: 99, class: INPUT_FIELD)
        p(class: FORM_HINT) { plain "Lower number = higher priority. Priority 1 is tried first." }
      end
    end

    def enabled_methods_field
      selected = @connection ? Array(@connection["enabled_methods"]) : []

      div(class: "flex flex-col gap-2") do
        p(class: FIELD_LABEL) { plain "Enabled payment methods" }
        div(class: "flex flex-col gap-2") do
          METHODS.each do |m|
            checked = selected.include?(m[:value]) || selected.empty?
            label(class: "flex items-center gap-3 cursor-pointer") do
              input(type: "checkbox", name: "enabled_methods[]",
                    value: m[:value], checked: checked,
                    class: "w-4 h-4 rounded text-brand-600 border-gray-300 cursor-pointer")
              span(class: "text-[13.5px] text-gray-700") { plain m[:label] }
            end
          end
        end
        p(class: FORM_HINT) { plain "Select which payment methods this PSP will handle." }
      end
    end

    def credentials_section
      div(class: "flex flex-col gap-4 pt-1 border-t border-gray-100") do
        p(class: "text-[12px] font-semibold text-gray-500 uppercase tracking-wide pt-1") do
          plain "API Credentials"
        end

        div(class: "flex flex-col gap-1") do
          label(for: "api_key", class: FIELD_LABEL) { plain "API Key" }
          input(type: "text", name: "api_key", id: "api_key",
                placeholder: "pk_live_…", class: INPUT_FIELD, autocomplete: "off")
        end

        div(class: "flex flex-col gap-1") do
          label(for: "secret_key", class: FIELD_LABEL) { plain "Secret Key" }
          input(type: "password", name: "secret_key", id: "secret_key",
                placeholder: "sk_live_…", class: INPUT_FIELD, autocomplete: "new-password")
          p(class: FORM_HINT) { plain "Your secret key is encrypted and stored securely." }
        end

        div(class: "flex flex-col gap-1") do
          label(for: "base_url", class: FIELD_LABEL) { plain "Base URL (optional)" }
          input(type: "url", name: "base_url", id: "base_url",
                placeholder: "Leave blank to use the provider's default endpoint",
                class: INPUT_FIELD)
          p(class: FORM_HINT) { plain "Only set this if you're using a custom API endpoint." }
        end
      end
    end
  end
end
