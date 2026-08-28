module Auth
  class OtpPage < ApplicationComponent
    def initialize(csrf_token:)
      @csrf_token = csrf_token
    end

    def view_template
      render Auth::Shell.new(
        title: "Two-factor verification",
        subtitle: "Enter the 6-digit code from your authenticator app."
      ) do
        form action: user_session_path,
             method: :post,
             class: "space-y-5" do
          input type: :hidden, name: :authenticity_token, value: @csrf_token

          div class: "flex flex-col items-center" do
            label for: "user_otp_attempt",
                  class: "block text-sm font-medium text-gray-700 mb-3" do
              plain "Verification code"
            end
            input(
              type: :text,
              id: "user_otp_attempt",
              name: "user[otp_attempt]",
              inputmode: "numeric",
              pattern: "[0-9]*",
              maxlength: "6",
              autocomplete: "one-time-code",
              autofocus: true,
              required: true,
              placeholder: "000 000",
              class: "w-44 text-center text-3xl font-mono tracking-[0.4em] rounded-lg border " \
                     "border-gray-200 px-4 py-3 text-gray-900 placeholder:text-gray-300 " \
                     "focus:outline-none focus:ring-2 focus:ring-teal-400"
            )
            p class: "mt-2 text-xs text-gray-400" do
              plain "Code refreshes every 30 seconds"
            end
          end

          button(
            type: :submit,
            class: "#{UI::Theme::BUTTON_PRIMARY} w-full justify-center py-2.5"
          ) do
            plain "Verify"
          end

          div class: "text-center" do
            a href: new_user_session_path,
              class: "text-xs text-gray-400 hover:text-gray-600 transition-colors" do
              plain "Use a different account"
            end
          end
        end
      end
    end
  end
end
