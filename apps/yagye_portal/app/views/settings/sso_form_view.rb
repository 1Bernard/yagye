# frozen_string_literal: true

module Settings
  class SsoFormView < ApplicationComponent
    include UI::Theme

    FIELD_CLASS = "w-full rounded-xl border border-gray-200 bg-gray-50 px-3 py-2.5 text-[13px] " \
                  "text-gray-900 focus:outline-none focus:bg-white focus:border-blue-400 " \
                  "focus:ring-2 focus:ring-blue-500/10 transition-all"

    LABEL_CLASS = "block text-[10.5px] font-semibold uppercase tracking-[0.1em] text-gray-400 mb-1.5"

    def initialize(config:, action:)
      @config = config
      @action = action
    end

    def view_template
      render Layout::Shell.new(
        active_nav: :settings,
        title:      form_title,
        breadcrumbs: [
          { label: "Settings", href: settings_path },
          { label: "Single Sign-On", href: settings_path(tab: "sso") },
          { label: form_title }
        ]
      ) do
        div(class: "max-w-xl") do
          div(class: "rounded-2xl border border-gray-200 bg-white px-6 py-6") do
            form(
              action: form_action,
              method: :post,
              class: "space-y-5"
            ) do
              input type: :hidden, name: :authenticity_token, value: helpers.form_authenticity_token
              if @action == :edit
                input type: :hidden, name: "_method", value: "patch"
              end

              field("Name", :name, type: :text,
                    placeholder: "Acme Corp SSO",
                    hint: "Shown to users on the sign-in button")

              field("Email domain", :email_domain, type: :text,
                    placeholder: "acme.com",
                    hint: "Users with this domain will see the SSO button")

              field("Merchant code", :merchant_code, type: :text,
                    placeholder: "mch_01abc...",
                    hint: "The enterprise merchant this SSO config belongs to")

              field("IdP SSO target URL", :idp_sso_target_url, type: :url,
                    placeholder: "https://login.okta.com/app/.../sso/saml",
                    hint: "Your IdP's SAML redirect endpoint")

              field("IdP entity ID", :idp_entity_id, type: :text,
                    placeholder: "http://www.okta.com/...",
                    hint: "Optional — leave blank if your IdP doesn't require it")

              div do
                label(class: LABEL_CLASS) { plain "IdP signing certificate (PEM)" }
                textarea(
                  name: "sso_configuration[idp_cert]",
                  rows: 6,
                  placeholder: "-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----",
                  class: FIELD_CLASS + " font-mono text-[11.5px]"
                ) { plain @config.idp_cert.to_s }
                p(class: "mt-1 text-[11px] text-gray-400") do
                  plain "Paste the X.509 certificate from your IdP metadata (without the BEGIN/END lines is also fine)"
                end
              end

              if @action == :edit
                label(class: "flex items-center gap-2.5 cursor-pointer") do
                  input(
                    type: :checkbox,
                    name: "sso_configuration[active]",
                    value: "1",
                    checked: @config.active?,
                    class: UI::Theme::CHECKBOX
                  )
                  span(class: "text-[13px] text-gray-700") { plain "Configuration is active" }
                end
              end

              div(class: "flex items-center gap-3 pt-2") do
                button(
                  type: :submit,
                  class: "inline-flex items-center gap-2 text-sm font-semibold text-white " \
                         "rounded-xl px-5 py-2.5 transition-opacity hover:opacity-90",
                  style: "background-color:#{BRAND}"
                ) { plain @action == :new ? "Create configuration" : "Save changes" }

                a(href: settings_path(tab: "sso"),
                  class: "text-[13px] font-medium text-gray-500 hover:text-gray-700 transition-colors") do
                  plain "Cancel"
                end
              end
            end
          end
        end
      end
    end

    private

    def field(label_text, attr, type: :text, placeholder: nil, hint: nil)
      div do
        label(class: LABEL_CLASS) { plain label_text }
        input(
          type: type,
          name: "sso_configuration[#{attr}]",
          value: @config.public_send(attr).to_s,
          placeholder: placeholder,
          class: FIELD_CLASS
        )
        p(class: "mt-1 text-[11px] text-gray-400") { plain hint } if hint
      end
    end

    def form_title
      @action == :new ? "New SSO Configuration" : "Edit SSO Configuration"
    end

    def form_action
      @action == :new ? settings_sso_index_path : settings_sso_path(@config)
    end
  end
end
