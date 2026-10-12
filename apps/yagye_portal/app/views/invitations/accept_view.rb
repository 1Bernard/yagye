# frozen_string_literal: true

module Invitations
  class AcceptView < ApplicationComponent
    include UI::Theme

    def initialize(user:, membership:, token:, csrf_token:)
      @user       = user
      @membership = membership
      @token      = token
      @csrf_token = csrf_token
    end

    def view_template
      render Auth::Shell.new(
        title:    "Accept your invitation",
        subtitle: "You've been invited to #{@membership.merchant_name}. Set a password to activate your account."
      ) do
        render UI::ErrorSummary.new(errors: @user.errors)

        div class: "mb-5 rounded-xl border border-blue-100 bg-blue-50 px-4 py-3" do
          p class: "text-[12.5px] text-blue-700" do
            plain "Invited by "
            strong { plain @membership.invited_by&.full_name || "your team" }
            plain " · expires #{fmt_date(@membership.invitation_expires_at)}"
          end
        end

        form action: accept_invitation_path(@token), method: :post, class: "space-y-5" do
          input type: :hidden, name: :authenticity_token, value: @csrf_token
          input type: :hidden, name: "_method", value: "patch"

          # Email — display only, not editable
          div(class: "flex flex-col gap-1.5") do
            label(for: "user_email", class: TEXT_LABEL) { plain "Email" }
            input(
              type:     :email,
              id:       "user_email",
              value:    @user.email,
              disabled: true,
              class:    "w-full rounded-xl border border-gray-200 bg-gray-100 px-3 py-3 " \
                        "text-sm text-gray-500 cursor-not-allowed"
            )
          end

          render UI::InputField.new(
            name:              "user[password]",
            id:                "user_password",
            label:             "Password",
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
            label:             "Confirm password",
            type:              "password",
            icon:              :lock,
            toggle_visibility: true,
            autocomplete:      "new-password",
            required:          true,
            placeholder:       "••••••••"
          )

          button(
            type:  :submit,
            class: "w-full inline-flex items-center justify-center rounded-xl px-4 py-3.5 " \
                   "text-sm font-semibold text-white transition-opacity hover:opacity-90 shadow-lg",
            style: "background-color: #3D47F5",
            data: {
              controller: "loading-button",
              action: "click->loading-button#start",
              loading_button_loading_text_value: "Activating…"
            }
          ) do
            render UI::Icon.new(:spinner, class: "w-4 h-4 mr-2 animate-spin hidden",
                                          data: { loading_button_target: "spinner" })
            span(data: { loading_button_target: "label" }) { plain "Activate account" }
          end
        end
      end
    end
  end
end
