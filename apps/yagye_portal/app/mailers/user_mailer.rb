# frozen_string_literal: true

class UserMailer < ApplicationMailer
  def invitation_instructions(user, membership, raw_token)
    @user        = user
    @merchant    = membership.merchant_name
    @invited_by  = membership.invited_by&.full_name || "Your team"
    @accept_url  = accept_invitation_url(raw_token, host: mailer_host)
    @expires_at  = membership.invitation_expires_at

    mail(
      to:      user.email,
      subject: "You've been invited to #{@merchant} on Yagye"
    )
  end

  def staff_invitation_instructions(user, invited_by, raw_token, expires_at)
    @user        = user
    @invited_by  = invited_by&.full_name || "Your team"
    @accept_url  = accept_invitation_url(raw_token, host: mailer_host)
    @expires_at  = expires_at

    mail(
      to:      user.email,
      subject: "You've been invited to join Yagye"
    )
  end

  private

  def mailer_host
    ENV.fetch("PORTAL_HOST", Rails.application.config.action_mailer.default_url_options&.fetch(:host, "portal.yagye.com"))
  end
end
