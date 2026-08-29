module Auth
  class ResetPasswordPage < ApplicationComponent
    ICON_INPUT = "w-full rounded-xl border border-gray-200 bg-gray-50 pl-9 pr-3 py-3 text-[13.5px] " \
                 "text-gray-900 placeholder:text-gray-400 " \
                 "focus:outline-none focus:bg-white focus:border-blue-400 focus:ring-2 focus:ring-blue-500/10 transition-all"

    FIELD_LABEL = "block text-[10px] font-semibold uppercase tracking-[0.1em] text-gray-600 mb-1.5"

    def initialize(resource:, csrf_token:, token:)
      @resource   = resource
      @csrf_token = csrf_token
      @token      = token
    end

    def view_template
      render Auth::Shell.new(
        title: "Set new password",
        subtitle: "Choose a strong password for your account."
      ) do
        render UI::ErrorSummary.new(errors: @resource.errors)

        form action: user_password_path, method: :post, class: "space-y-5" do
          input type: :hidden, name: :authenticity_token, value: @csrf_token
          input type: :hidden, name: "_method", value: "patch"
          input type: :hidden, name: "user[reset_password_token]", value: @token

          div do
            label for: "user_password", class: FIELD_LABEL do
              plain "New password"
            end
            div class: "relative" do
              div class: "absolute inset-y-0 left-3 flex items-center pointer-events-none text-gray-500" do
                render UI::Icon.new(:lock, class: "w-4 h-4")
              end
              input(
                type: :password,
                id: "user_password",
                name: "user[password]",
                autocomplete: "new-password",
                autofocus: true,
                required: true,
                placeholder: "••••••••",
                class: ICON_INPUT
              )
            end
            p class: "mt-1 text-[11px] text-gray-400" do
              plain "At least 12 characters."
            end
          end

          div do
            label for: "user_password_confirmation", class: FIELD_LABEL do
              plain "Confirm new password"
            end
            div class: "relative" do
              div class: "absolute inset-y-0 left-3 flex items-center pointer-events-none text-gray-500" do
                render UI::Icon.new(:lock, class: "w-4 h-4")
              end
              input(
                type: :password,
                id: "user_password_confirmation",
                name: "user[password_confirmation]",
                autocomplete: "new-password",
                required: true,
                placeholder: "••••••••",
                class: ICON_INPUT
              )
            end
          end

          button(
            type: :submit,
            class: "w-full inline-flex items-center justify-center rounded-xl px-4 py-3 " \
                   "text-[13.5px] font-semibold text-white transition-opacity hover:opacity-90 shadow-md",
            style: "background-color: #3D47F5"
          ) do
            plain "Set new password"
          end
        end

        div class: "mt-5 text-center" do
          a href: new_user_session_path,
            class: "text-sm #{UI::Theme::LINK_MUTED}" do
            plain "Back to sign in"
          end
        end
      end
    end
  end
end
