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
        error_summary if @resource.errors.any?

        form action: user_password_path, method: :post, class: "space-y-5" do
          input type: :hidden, name: :authenticity_token, value: @csrf_token
          input type: :hidden, name: "_method", value: "patch"
          input type: :hidden, name: "user[reset_password_token]", value: @token

          div do
            label for: "user_password",
                  class: "block text-sm font-medium text-gray-700 mb-1.5" do
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
            p class: "mt-1 text-xs text-gray-500" do
              plain "At least 12 characters."
            end
          end

          div do
            label for: "user_password_confirmation",
                  class: "block text-sm font-medium text-gray-700 mb-1.5" do
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
            class: "text-sm text-gray-400 hover:text-gray-600 transition-colors" do
            plain "Back to sign in"
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
