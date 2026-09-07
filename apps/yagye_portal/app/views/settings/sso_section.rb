# frozen_string_literal: true

module Settings
  class SsoSection < ApplicationComponent
    include UI::Theme

    def initialize(current_user:, configs: [])
      @current_user = current_user
      @configs      = configs
    end

    def view_template
      div(class: "flex flex-col gap-5") do
        if @current_user.internal_staff?
          ops_view
        else
          merchant_view
        end
      end
    end

    private

    # ── Ops view — full CRUD ──────────────────────────────────────────────────

    def ops_view
      # Header card
      div(class: "rounded-2xl border border-gray-200 bg-white px-6 py-5") do
        div(class: "flex items-start justify-between gap-4 mb-5") do
          div do
            p(class: "text-[15px] font-bold text-gray-900 mb-1") { plain "SSO Configurations" }
            p(class: TYPE_CAPTION) do
              plain "SAML 2.0 single sign-on for enterprise merchants. Each domain maps to one IdP."
            end
          end
          a(
            href: new_settings_sso_path,
            class: "shrink-0 inline-flex items-center gap-1.5 text-[12.5px] font-semibold " \
                   "text-white rounded-xl px-4 py-2 transition-opacity hover:opacity-90",
            style: "background-color:#{BRAND}"
          ) do
            render UI::Icon.new(:plus, class: "w-3.5 h-3.5")
            plain "Add configuration"
          end
        end

        if @configs.empty?
          p(class: "text-center py-8 #{TYPE_CAPTION}") { plain "No SSO configurations yet." }
        else
          div(class: "divide-y divide-gray-100") do
            @configs.each { |c| config_row(c) }
          end
        end
      end

      sp_metadata_card
    end

    def config_row(config)
      div(class: "flex items-center justify-between gap-4 py-3.5") do
        div(class: "flex-1 min-w-0") do
          div(class: "flex items-center gap-2 mb-0.5") do
            p(class: "text-[13.5px] font-semibold text-gray-900 truncate") { plain config.name }
            if config.active?
              span(class: "text-[10px] font-bold px-2 py-0.5 rounded-full",
                   style: "background:#dcfce7;color:#15803d") { plain "Active" }
            else
              span(class: "text-[10px] font-bold px-2 py-0.5 rounded-full bg-gray-100 text-gray-500") do
                plain "Inactive"
              end
            end
          end
          p(class: TYPE_CAPTION) do
            plain "@#{config.email_domain} · #{config.merchant_code}"
          end
        end
        div(class: "flex items-center gap-2 shrink-0") do
          a(href: edit_settings_sso_path(config),
            class: "text-[12px] font-medium text-gray-500 hover:text-gray-700 px-3 py-1.5 " \
                   "rounded-lg border border-gray-200 hover:bg-gray-50 transition-colors") do
            plain "Edit"
          end
          button(
            form: "delete-sso-#{config.id}",
            type: "submit",
            class: "text-[12px] font-medium text-red-600 hover:text-red-700 px-3 py-1.5 " \
                   "rounded-lg border border-red-100 hover:bg-red-50 transition-colors",
            data: { confirm: "Remove SSO for @#{config.email_domain}?" }
          ) { plain "Remove" }
          form(id: "delete-sso-#{config.id}",
               action: settings_sso_path(config),
               method: :post, class: "hidden") do
            input type: :hidden, name: "_method", value: "delete"
            input type: :hidden, name: :authenticity_token, value: helpers.form_authenticity_token
          end
        end
      end
    end

    # ── Merchant view — read-only SP metadata ────────────────────────────────

    def merchant_view
      config = @configs.first

      div(class: "rounded-2xl border border-gray-200 bg-white px-6 py-5") do
        p(class: "text-[15px] font-bold text-gray-900 mb-1") { plain "Single Sign-On" }
        p(class: "#{TYPE_CAPTION} mb-5") do
          plain "Your organisation uses SAML SSO. Give the details below to your IT team to configure your IdP."
        end

        if config
          metadata_row("ACS URL (Reply URL)",
                       "#{sp_base_url}/auth/saml/callback")
          metadata_row("Entity ID (Audience URI)",
                       "#{sp_base_url}/auth/saml/metadata")
          metadata_row("Name ID format",
                       "urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress")
          metadata_row("Sign-in domain", "@#{config.email_domain}")
        else
          p(class: "text-center py-8 #{TYPE_CAPTION}") do
            plain "SSO is not yet configured for your account. Contact Yagye support."
          end
        end
      end
    end

    def metadata_row(label, value)
      div(class: "mb-4 last:mb-0") do
        p(class: "text-[11px] font-semibold uppercase tracking-[0.08em] text-gray-400 mb-1") do
          plain label
        end
        div(class: "flex items-center gap-2 bg-gray-50 border border-gray-200 rounded-xl px-4 py-2.5") do
          code(class: "flex-1 text-[12.5px] text-gray-700 font-mono break-all") { plain value }
        end
      end
    end

    def sp_metadata_card
      div(class: "rounded-2xl border border-gray-200 bg-gray-50 px-6 py-4") do
        p(class: "text-[12px] font-semibold text-gray-600 mb-1") { plain "Service Provider (SP) details" }
        p(class: TYPE_CAPTION) do
          plain "Share these with enterprise merchants to configure their IdP."
        end
        div(class: "mt-3 space-y-2") do
          metadata_row("ACS URL", "#{sp_base_url}/auth/saml/callback")
          metadata_row("Entity ID", "#{sp_base_url}/auth/saml/metadata")
        end
      end
    end

    def sp_base_url
      ENV.fetch("SP_BASE_URL", "https://portal.yagye.com")
    end
  end
end
