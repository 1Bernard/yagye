# frozen_string_literal: true

module Account
  class InvitationsController < ApplicationController
    skip_before_action :authenticate_user!

    def show
      skip_authorization
      @invitation = find_valid_invitation
      return redirect_to new_user_session_path, alert: invitation_invalid_message unless @invitation

      render Invitations::AcceptView.new(
        invitation: @invitation,
        token:      params[:token],
        csrf_token: form_authenticity_token
      )
    end

    def update
      skip_authorization
      @invitation = find_valid_invitation
      return redirect_to new_user_session_path, alert: invitation_invalid_message unless @invitation

      user     = @invitation.user
      password = params.dig(:user, :password).to_s
      confirm  = params.dig(:user, :password_confirmation).to_s

      if user.update(password: password, password_confirmation: confirm)
        accept_invitation!
        sign_in user
        redirect_to settings_totp_new_path,
                    notice: "#{welcome_message} Set up two-factor authentication to secure your account."
      else
        render Invitations::AcceptView.new(
          invitation: @invitation,
          token:      params[:token],
          csrf_token: form_authenticity_token
        ), status: :unprocessable_entity
      end
    end

    private

    # Returns an InvitationContext (user, invited_by_name, expires_at, context_name, is_staff)
    # or nil when the token is missing, invalid or expired.
    def find_valid_invitation
      return unless params[:token].present?

      # Merchant path: token lives on MerchantMembership
      membership = MerchantMembership.find_by_invitation_token(params[:token])
      if membership&.invitation_valid?
        @membership = membership
        return InvitationContext.new(
          user:            membership.user,
          invited_by_name: membership.invited_by&.full_name || "Your team",
          expires_at:      membership.invitation_expires_at,
          context_name:    membership.merchant_name,
          is_staff:        false
        )
      end

      # Staff path: token lives on User
      staff_user = User.find_by_staff_invitation_token(params[:token])
      if staff_user&.staff_invitation_valid?
        @staff_user = staff_user
        return InvitationContext.new(
          user:            staff_user,
          invited_by_name: staff_user.invited_by&.full_name || "Your team",
          expires_at:      staff_user.invitation_expires_at,
          context_name:    "Yagye Operations",
          is_staff:        true
        )
      end

      nil
    end

    def accept_invitation!
      if @membership
        @membership.accept!
      else
        @staff_user.accept_staff_invitation!
      end
    end

    def welcome_message
      @membership ? "Welcome to #{@membership.merchant_name}!" : "Welcome to Yagye!"
    end

    def invitation_invalid_message
      "This invitation link is invalid or has expired. Please ask your team admin to resend it."
    end
  end
end
