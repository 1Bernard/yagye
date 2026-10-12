module Auth
  class ResetPasswordView < ApplicationComponent
    include UI::Theme

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

          render UI::InputField.new(
            name:              "user[password]",
            id:                "user_password",
            label:             "New password",
            type:              "password",
            icon:              :lock,
            toggle_visibility: true,
            autocomplete:      "new-password",
            autofocus:         true,
            required:          true,
            placeholder:       "••••••••",
            hint:              "At least 12 characters."
          )

          render UI::InputField.new(
            name:              "user[password_confirmation]",
            id:                "user_password_confirmation",
            label:             "Confirm new password",
            type:              "password",
            icon:              :lock,
            toggle_visibility: true,
            autocomplete:      "new-password",
            required:          true,
            placeholder:       "••••••••"
          )

          button(
            type: :submit,
            class: "w-full inline-flex items-center justify-center rounded-xl px-4 py-3.5 " \
                   "text-sm font-semibold text-white transition-opacity hover:opacity-90 shadow-lg",
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
