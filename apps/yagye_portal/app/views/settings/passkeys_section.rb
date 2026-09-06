# frozen_string_literal: true

module Settings
  class PasskeysSection < ApplicationComponent
    include UI::Theme

    def initialize(current_user:)
      @current_user = current_user
    end

    def view_template
      creds = @current_user.passkey_credentials.order(created_at: :desc)

      div(
        class: "rounded-2xl border border-gray-100 overflow-hidden",
        data: {
          controller: "passkey",
          passkey_register_challenge_url_value: settings_passkey_register_challenge_path,
          passkey_register_url_value:           settings_passkeys_path,
          passkey_csrf_token_value:             form_authenticity_token
        }
      ) do
        div(class: "px-6 py-5 border-b border-gray-100 flex items-center justify-between") do
          div do
            p(class: TYPE_TITLE) { plain "Passkeys" }
            p(class: "#{TYPE_CAPTION} mt-[3px]") do
              plain "Sign in with Touch ID, Face ID, or a hardware security key — no password needed."
            end
          end
          button(
            type: "button",
            class: "inline-flex items-center gap-[6px] px-[11px] py-[7px] rounded-xl " \
                   "border border-gray-200 text-[12.5px] font-semibold text-gray-700 " \
                   "bg-white hover:bg-gray-50 transition-colors cursor-pointer",
            data: { action: "click->passkey#register" }
          ) do
            span(class: "flex w-[14px] h-[14px]") { render UI::Icon.new(:key, class: "w-full h-full") }
            plain "Add passkey"
          end
        end

        if creds.empty?
          empty_state
        else
          creds.each { |cred| credential_row(cred) }
        end
      end
    end

    private

    def empty_state
      div(class: "px-6 py-10 flex flex-col items-center gap-3 text-center") do
        div(class: "w-12 h-12 rounded-2xl bg-gray-100 flex items-center justify-center mb-1") do
          span(class: "flex w-[20px] h-[20px] text-gray-400") do
            render UI::Icon.new(:key, class: "w-full h-full")
          end
        end
        p(class: "text-[13px] font-semibold text-gray-900") { plain "No passkeys enrolled" }
        p(class: TYPE_CAPTION) do
          plain "Click “Add passkey” to register this device or a security key."
        end
      end
    end

    def credential_row(cred)
      div(class: "group flex items-center gap-4 px-6 py-[14px] border-b border-gray-50 last:border-0 hover:bg-gray-50/60 transition-colors") do
        div(class: "w-9 h-9 rounded-xl bg-gray-100 border border-gray-200 flex items-center justify-center flex-shrink-0") do
          span(class: "flex w-[15px] h-[15px] text-gray-400") do
            render UI::Icon.new(:key, class: "w-full h-full")
          end
        end

        div(class: "flex-1 min-w-0") do
          p(class: TYPE_BODY_MD) { plain cred.nickname || "Passkey" }
          p(class: TYPE_CAPTION) do
            added = cred.created_at.strftime("%d %b %Y")
            last  = cred.last_used_at&.strftime("%d %b %Y, %H:%M") || "Never used"
            plain "Added #{added} · Last used: #{last}"
          end
        end

        form(action: settings_remove_passkey_path(cred), method: "post",
             data: { turbo_confirm: "Remove this passkey? You won't be able to use it to sign in." }) do
          input(type: "hidden", name: "_method",            value: "delete")
          input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
          button(
            type: "submit",
            class: "flex w-7 h-7 rounded-lg items-center justify-center text-gray-300 " \
                   "hover:text-red-500 hover:bg-red-50 transition-colors border-0 bg-transparent " \
                   "cursor-pointer ml-1 opacity-0 group-hover:opacity-100"
          ) do
            span(class: "flex w-[14px] h-[14px]") { render UI::Icon.new(:x, class: "w-full h-full") }
          end
        end
      end
    end
  end
end
