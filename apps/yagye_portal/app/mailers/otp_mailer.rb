# frozen_string_literal: true

class OtpMailer < ApplicationMailer
  def email_otp(user:, code:)
    @code       = code
    @user_name  = user.first_name.presence || user.email
    @expires    = 10
    mail(to: user.email, subject: "Your Yagye sign-in code: #{code}")
  end

  def sign_in_alert(user:, ip:, time:)
    @user_name = user.first_name.presence || user.email
    @ip        = ip
    @time      = time.strftime("%d %b %Y at %H:%M UTC")
    mail(to: user.email, subject: "New sign-in to your Yagye account")
  end
end
