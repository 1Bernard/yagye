module Auth
  class ForgotPasswordPage < ApplicationComponent
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
            label for: "user_email", class: "#{UI::Theme::FORM_LABEL} mb-1.5" do
              plain "Email address"
            end
            input(
              type: :email,
              id: "user_email",
              name: "user[email]",
              value: @resource.email.to_s,
              autocomplete: "email",
              autofocus: true,
              required: true,
              class: "#{UI::Theme::INPUT} w-full"
            )
          end

          button(
            type: :submit,
            class: "#{UI::Theme::BUTTON_PRIMARY} w-full justify-center py-2.5"
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
