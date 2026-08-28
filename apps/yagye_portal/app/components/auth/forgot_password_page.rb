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
        error_summary if @resource.errors.any?

        form action: user_password_path, method: :post, class: "space-y-5" do
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

          button(
            type: :submit,
            class: "#{UI::Theme::BUTTON_PRIMARY} w-full justify-center py-2.5"
          ) do
            plain "Send reset instructions"
          end
        end

        div class: "mt-5 text-center" do
          a href: new_user_session_path,
            class: "text-sm text-teal-600 hover:text-teal-700 transition-colors" do
            plain "← Back to sign in"
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
