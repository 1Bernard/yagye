# frozen_string_literal: true

module Auth
  # Shown only when the Stimulus sso-domain controller confirms the entered email
  # domain has an active SsoConfiguration. Initially hidden; JS sets hidden = false.
  class SsoButton < ApplicationComponent
    def initialize(check_url:, initiate_url:)
      @check_url    = check_url
      @initiate_url = initiate_url
    end

    def view_template
      div(hidden: true, data: { sso_domain_target: "ssoSection" }) do
        div(class: "flex items-center gap-3") do
          div(class: "flex-1 h-px bg-gray-200")
          span(class: "text-[11px] text-gray-400 font-medium flex-shrink-0") { plain "or" }
          div(class: "flex-1 h-px bg-gray-200")
        end

        a(
          href: @initiate_url,
          class: "mt-3 w-full inline-flex items-center justify-center gap-2 rounded-xl " \
                 "px-4 py-3.5 text-[13.5px] font-semibold text-gray-700 bg-white " \
                 "border border-gray-200 hover:bg-gray-50 transition-colors shadow-sm",
          data: { sso_domain_target: "ssoLink" }
        ) do
          raw safe(building_icon)
          span(data: { sso_domain_target: "ssoLabel" }) { plain "Sign in with SSO" }
        end
      end
    end

    private

    def building_icon
      <<~SVG
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none"
             stroke="currentColor" stroke-width="1.8"
             stroke-linecap="round" stroke-linejoin="round">
          <rect x="2" y="7" width="20" height="14" rx="2"/>
          <path d="M16 7V5a2 2 0 0 0-2-2h-4a2 2 0 0 0-2 2v2"/>
          <line x1="12" y1="12" x2="12" y2="16"/>
          <line x1="10" y1="14" x2="14" y2="14"/>
        </svg>
      SVG
    end
  end
end
