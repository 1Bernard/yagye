module Auth
  class SignInView < ApplicationComponent
    ICON_INPUT = "w-full rounded-xl border border-gray-200 bg-gray-50 pl-9 pr-3 py-3.5 text-[13.5px] " \
                 "text-gray-900 placeholder:text-gray-300 " \
                 "focus:outline-none focus:bg-white focus:border-blue-400 focus:ring-2 focus:ring-blue-500/10 transition-all"

    FIELD_LABEL = "block text-[10px] font-semibold uppercase tracking-[0.12em] text-gray-400 mb-2"

    def initialize(resource:, csrf_token:)
      @resource   = resource
      @csrf_token = csrf_token
    end

    def view_template
      render Auth::Shell.new(
        title: "The simplest way to pay across Africa",
        subtitle: "Enter your credentials to access your account"
      ) do
        render UI::ErrorSummary.new(errors: @resource.errors)

        form action: user_session_path, method: :post, class: "space-y-5" do
          input type: :hidden, name: :authenticity_token, value: @csrf_token

          # ── Email ──────────────────────────────────────────────────────────
          div do
            label for: "user_email", class: FIELD_LABEL do
              plain "Email address"
            end
            div class: "relative" do
              div class: "absolute inset-y-0 left-3 flex items-center pointer-events-none text-gray-500" do
                render UI::Icon.new(:mail, class: "w-4 h-4")
              end
              input(
                type: :email,
                id: "user_email",
                name: "user[email]",
                value: @resource.email.to_s,
                autocomplete: "email",
                autofocus: true,
                required: true,
                placeholder: "you@company.com",
                class: ICON_INPUT
              )
            end
          end

          # ── Password ───────────────────────────────────────────────────────
          div do
            div class: "flex items-center justify-between mb-1.5" do
              label for: "user_password", class: FIELD_LABEL do
                plain "Password"
              end
              a href: new_user_password_path,
                class: "text-[11px] font-semibold text-blue-600 hover:text-blue-700 transition-colors" do
                plain "Forgot password?"
              end
            end
            div class: "relative" do
              div class: "absolute inset-y-0 left-3 flex items-center pointer-events-none text-gray-500" do
                render UI::Icon.new(:lock, class: "w-4 h-4")
              end
              input(
                type: :password,
                id: "user_password",
                name: "user[password]",
                autocomplete: "current-password",
                required: true,
                placeholder: "••••••••",
                class: ICON_INPUT
              )
            end
          end

          # ── Remember me ────────────────────────────────────────────────────
          label class: "flex items-center gap-2.5 cursor-pointer" do
            input(
              type: :checkbox,
              name: "user[remember_me]",
              value: "1",
              class: UI::Theme::CHECKBOX
            )
            span class: "text-[12.5px] text-gray-600 select-none" do
              plain "Stay signed in for 30 days"
            end
          end

          # ── Submit + trust signal ──────────────────────────────────────────
          div do
            button(
              type: :submit,
              class: "w-full inline-flex items-center justify-center rounded-xl px-4 py-3.5 " \
                     "text-sm font-semibold text-white transition-opacity hover:opacity-90 shadow-lg",
              style: "background-color: #3D47F5"
            ) do
              plain "Sign in"
              render UI::Icon.new(:arrow_right, class: "w-4 h-4 ml-1")
            end

            div class: "flex items-center justify-center gap-1.5 mt-3.5 text-gray-500" do
              render UI::Icon.new(:shield, class: "w-3.5 h-3.5")
              span class: "text-[11px]" do
                plain "Secured with 256-bit TLS encryption"
              end
            end
          end

          # ── Passkey alternative ────────────────────────────────────────────
          div(class: "flex items-center gap-3") do
            div(class: "flex-1 h-px bg-gray-200")
            span(class: "text-[11px] text-gray-400 font-medium flex-shrink-0") { plain "or" }
            div(class: "flex-1 h-px bg-gray-200")
          end

          div(
            data: {
              controller: "passkey-auth",
              passkey_auth_challenge_url_value: users_passkey_challenge_path,
              passkey_auth_auth_url_value:      users_passkey_auth_path,
              passkey_auth_csrf_token_value:    @csrf_token
            }
          ) do
            button(
              type: "button",
              class: "w-full inline-flex items-center justify-center gap-2 rounded-xl px-4 py-3.5 " \
                     "text-[13.5px] font-semibold text-gray-700 bg-white border border-gray-200 " \
                     "hover:bg-gray-50 transition-colors cursor-pointer shadow-sm",
              data: { action: "click->passkey-auth#authenticate" }
            ) do
              raw safe('<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/></svg>')
              plain "Sign in with a passkey"
            end
          end
        end
      end
    end
  end
end
