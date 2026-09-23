# frozen_string_literal: true

module Invitations
  class AcceptView < ApplicationComponent
    ICON_INPUT = "w-full rounded-xl border border-gray-200 bg-gray-50 pl-9 pr-3 py-3.5 text-[13.5px] " \
                 "text-gray-900 placeholder:text-gray-300 " \
                 "focus:outline-none focus:bg-white focus:border-blue-400 focus:ring-2 focus:ring-blue-500/10 transition-all"

    FIELD_LABEL = "block text-[10px] font-semibold uppercase tracking-[0.12em] text-gray-400 mb-2"

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
            plain " · expires #{@membership.invitation_expires_at.strftime('%d %b %Y')}"
          end
        end

        form action: accept_invitation_path(@token), method: :post, class: "space-y-5" do
          input type: :hidden, name: :authenticity_token, value: @csrf_token
          input type: :hidden, name: "_method", value: "patch"

          div do
            label for: "user_email", class: FIELD_LABEL do
              plain "Email"
            end
            input(
              type:     :email,
              id:       "user_email",
              value:    @user.email,
              disabled: true,
              class:    "w-full rounded-xl border border-gray-200 bg-gray-100 px-3 py-3.5 " \
                        "text-[13.5px] text-gray-500 cursor-not-allowed"
            )
          end

          div do
            label for: "user_password", class: FIELD_LABEL do
              plain "Password"
            end
            div class: "relative" do
              div class: "absolute inset-y-0 left-3 flex items-center pointer-events-none text-gray-500" do
                render UI::Icon.new(:lock, class: "w-4 h-4")
              end
              input(
                type:         :password,
                id:           "user_password",
                name:         "user[password]",
                autocomplete: "new-password",
                autofocus:    true,
                required:     true,
                placeholder:  "••••••••",
                class:        ICON_INPUT
              )
            end
            p class: "mt-1 text-[11px] text-gray-400" do
              plain "At least 12 characters."
            end
          end

          div do
            label for: "user_password_confirmation", class: FIELD_LABEL do
              plain "Confirm password"
            end
            div class: "relative" do
              div class: "absolute inset-y-0 left-3 flex items-center pointer-events-none text-gray-500" do
                render UI::Icon.new(:lock, class: "w-4 h-4")
              end
              input(
                type:         :password,
                id:           "user_password_confirmation",
                name:         "user[password_confirmation]",
                autocomplete: "new-password",
                required:     true,
                placeholder:  "••••••••",
                class:        ICON_INPUT
              )
            end
          end

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
