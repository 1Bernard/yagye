# frozen_string_literal: true

module Account
  class InvitationsController < ApplicationController
    skip_before_action :authenticate_user!

    def show
      @membership = find_valid_membership
      return redirect_to new_user_session_path, alert: invitation_invalid_message unless @membership

      render Invitations::AcceptView.new(
        user:       @membership.user,
        membership: @membership,
        token:      params[:token],
        csrf_token: form_authenticity_token
      )
    end

    def update
      @membership = find_valid_membership
      return redirect_to new_user_session_path, alert: invitation_invalid_message unless @membership

      user = @membership.user
      password = params.dig(:user, :password).to_s
      confirmation = params.dig(:user, :password_confirmation).to_s

      if user.update(password: password, password_confirmation: confirmation)
        @membership.accept!
        sign_in user
        redirect_to root_path, notice: "Welcome to #{@membership.merchant_name}! Your account is ready."
      else
        render Invitations::AcceptView.new(
          user:       user,
          membership: @membership,
          token:      params[:token],
          csrf_token: form_authenticity_token
        ), status: :unprocessable_entity
      end
    end

    private

    def find_valid_membership
      return unless params[:token].present?

      membership = MerchantMembership.find_by_invitation_token(params[:token])
      membership&.invitation_valid? ? membership : nil
    end

    def invitation_invalid_message
      "This invitation link is invalid or has expired. Please ask your team admin to resend it."
    end
  end
end
