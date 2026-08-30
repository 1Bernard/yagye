module Auth
  class ForgotPasswordView < ApplicationComponent
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
        title: "Reset your password",
        subtitle: "We'll send a reset link to your email address."
      ) do
        render UI::ErrorSummary.new(errors: @resource.errors)

        form action: user_password_path, method: :post, class: "space-y-5" do
          input type: :hidden, name: :authenticity_token, value: @csrf_token

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

          button(
            type: :submit,
            class: "w-full inline-flex items-center justify-center rounded-xl px-4 py-3.5 " \
                   "text-sm font-semibold text-white transition-opacity hover:opacity-90 shadow-lg",
            style: "background-color: #3D47F5"
          ) do
            plain "Send reset instructions"
          end
        end

        div class: "mt-5 text-center" do
          a href: new_user_session_path,
            class: "text-sm #{UI::Theme::LINK_PRIMARY}" do
            plain "← Back to sign in"
          end
        end
      end
    end
  end
end
