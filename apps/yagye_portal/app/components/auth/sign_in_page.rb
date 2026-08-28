module Auth
  class SignInPage < ApplicationComponent
    def initialize(resource:, csrf_token:)
      @resource   = resource
      @csrf_token = csrf_token
    end

    def view_template
      render Auth::Shell.new(
        title: "Welcome back",
        subtitle: "Sign in to your Yagye account"
      ) do
        render UI::ErrorSummary.new(errors: @resource.errors)

        form action: user_session_path, method: :post, class: "space-y-5" do
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

          div do
            div class: "flex items-center justify-between mb-1.5" do
              label for: "user_password", class: UI::Theme::FORM_LABEL do
                plain "Password"
              end
              a href: new_user_password_path,
                class: "text-xs #{UI::Theme::LINK_PRIMARY}" do
                plain "Forgot password?"
              end
            end
            input(
              type: :password,
              id: "user_password",
              name: "user[password]",
              autocomplete: "current-password",
              required: true,
              class: "#{UI::Theme::INPUT} w-full"
            )
          end

          div do
            label for: "user_otp_attempt", class: "#{UI::Theme::FORM_LABEL} mb-1.5" do
              plain "Authenticator code"
            end
            input(
              type: :text,
              id: "user_otp_attempt",
              name: "user[otp_attempt]",
              inputmode: "numeric",
              pattern: "[0-9]*",
              maxlength: "6",
              autocomplete: "one-time-code",
              placeholder: "6-digit code",
              class: "#{UI::Theme::INPUT} w-full font-mono tracking-widest text-center"
            )
            p class: "mt-1 #{UI::Theme::FORM_MUTED}" do
              plain "Required once you've set up two-factor authentication."
            end
          end

          label class: "flex items-center gap-2.5 cursor-pointer" do
            input(
              type: :checkbox,
              name: "user[remember_me]",
              value: "1",
              class: UI::Theme::CHECKBOX
            )
            span class: UI::Theme::BODY do
              plain "Stay signed in for 30 days"
            end
          end

          button(
            type: :submit,
            class: "#{UI::Theme::BUTTON_PRIMARY} w-full justify-center py-2.5"
          ) do
            plain "Sign in"
          end
        end
      end
    end
  end
end
