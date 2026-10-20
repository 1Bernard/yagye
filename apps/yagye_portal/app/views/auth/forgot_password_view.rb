# frozen_string_literal: true

module Auth
  class ForgotPasswordView < ApplicationComponent
    include UI::Theme

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

          render UI::InputField.new(
            name:         "user[email]",
            id:           "user_email",
            label:        "Email address",
            type:         "email",
            value:        @resource.email.to_s,
            icon:         :mail,
            autocomplete: "email",
            autofocus:    true,
            required:     true,
            placeholder:  "you@company.com"
          )

          button(
            type: :submit,
            class: "w-full inline-flex items-center justify-center rounded-xl px-4 py-3.5 " \
                   "text-sm font-semibold text-white transition-opacity hover:opacity-90 shadow-lg",
            style: "background-color: #3D47F5"
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
