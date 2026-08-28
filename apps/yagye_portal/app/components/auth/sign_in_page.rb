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
        error_summary if @resource.errors.any?

        form action: user_session_path, method: :post, class: "space-y-5" do
          input type: :hidden, name: :authenticity_token, value: @csrf_token

          div do
            label for: "user_email",
                  class: "block text-sm font-medium text-gray-700 mb-1.5" do
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
              label for: "user_password",
                    class: "block text-sm font-medium text-gray-700" do
                plain "Password"
              end
              a href: new_user_password_path,
                class: "text-xs font-medium text-teal-600 hover:text-teal-700 transition-colors" do
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

          # OTP code — required for users with 2FA enrolled; ignored otherwise
          div do
            label for: "user_otp_attempt",
                  class: "block text-sm font-medium text-gray-700 mb-1.5" do
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
            p class: "mt-1 text-xs text-gray-400" do
              plain "Required once you've set up two-factor authentication."
            end
          end

          label class: "flex items-center gap-2.5 cursor-pointer" do
            input(
              type: :checkbox,
              name: "user[remember_me]",
              value: "1",
              class: "h-4 w-4 rounded border-gray-300 text-teal-500 focus:ring-teal-400"
            )
            span class: "text-sm text-gray-600" do
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

    private

    def error_summary
      div class: "mb-5 p-3 bg-red-50 border border-red-200 rounded-lg" do
        ul class: "text-xs text-red-600 space-y-0.5 list-disc list-inside" do
          @resource.errors.each do |error|
            li { plain error.full_message }
          end
        end
      end
    end
  end
end
