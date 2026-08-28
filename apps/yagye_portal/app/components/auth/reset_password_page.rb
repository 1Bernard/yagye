module Auth
  class ResetPasswordPage < ApplicationComponent
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
            label for: "user_password", class: "#{UI::Theme::FORM_LABEL} mb-1.5" do
              plain "New password"
            end
            input(
              type: :password,
              id: "user_password",
              name: "user[password]",
              autocomplete: "new-password",
              autofocus: true,
              required: true,
              class: "#{UI::Theme::INPUT} w-full"
            )
            p class: "mt-1 #{UI::Theme::FORM_HINT}" do
              plain "At least 12 characters."
            end
          end

          div do
            label for: "user_password_confirmation",
                  class: "#{UI::Theme::FORM_LABEL} mb-1.5" do
              plain "Confirm new password"
            end
            input(
              type: :password,
              id: "user_password_confirmation",
              name: "user[password_confirmation]",
              autocomplete: "new-password",
              required: true,
              class: "#{UI::Theme::INPUT} w-full"
            )
          end

          button(
            type: :submit,
            class: "#{UI::Theme::BUTTON_PRIMARY} w-full justify-center py-2.5"
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
