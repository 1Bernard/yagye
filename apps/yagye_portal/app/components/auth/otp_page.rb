module Auth
  class OtpPage < ApplicationComponent
    FIELD_LABEL = "block text-[10px] font-semibold uppercase tracking-[0.1em] text-gray-600 mb-1.5"

    def initialize(csrf_token:)
      @csrf_token = csrf_token
    end

    def view_template
      render Auth::Shell.new(
        title: "Two-factor verification",
        subtitle: "Enter the 6-digit code from your authenticator app."
      ) do
        form action: users_verify_otp_path,
             method: :post,
             class: "space-y-5" do
          input type: :hidden, name: :authenticity_token, value: @csrf_token

          div class: "flex flex-col items-center" do
            label for: "user_otp_attempt", class: "#{FIELD_LABEL} mb-3" do
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
              class: "w-44 text-center text-3xl font-mono tracking-[0.4em] rounded-xl " \
                     "border border-gray-200 bg-gray-50 px-4 py-3 text-gray-900 placeholder:text-gray-300 " \
                     "focus:outline-none focus:bg-white focus:border-blue-400 focus:ring-2 focus:ring-blue-500/10 transition-all"
            )
            p class: "mt-2 text-[11px] text-gray-400" do
              plain "Code refreshes every 30 seconds"
            end
          end

          button(
            type: :submit,
            class: "w-full inline-flex items-center justify-center rounded-xl px-4 py-3 " \
                   "text-[13.5px] font-semibold text-white transition-opacity hover:opacity-90 shadow-md",
            style: "background-color: #3D47F5"
          ) do
            plain "Verify"
          end

          div class: "text-center" do
            a href: new_user_session_path,
              class: "text-xs #{UI::Theme::LINK_MUTED}" do
              plain "Use a different account"
            end
          end
        end
      end
    end
  end
end
