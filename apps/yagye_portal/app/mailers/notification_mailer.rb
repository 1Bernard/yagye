# frozen_string_literal: true

class NotificationMailer < ApplicationMailer
  EVENT_SUBJECTS = {
    "payment_success"  => "Payment received",
    "payment_failed"   => "Payment failed",
    "dispute_opened"   => "New dispute opened",
    "dispute_resolved" => "Dispute resolved",
    "kyb_status"       => "KYB status update",
    "new_team_member"  => "New team member joined",
    "api_key_created"  => "New API key generated",
    "login_new_device" => "New device sign-in detected"
  }.freeze

  def notification_email(user, notification)
    @user         = user
    @notification = notification
    @subject      = EVENT_SUBJECTS.fetch(notification.event_type, notification.title)
    @action_url   = notification.link ? portal_url(notification.link) : portal_root_url

    mail(to: user.email, subject: "[Yagye] #{@subject}")
  end

  private

  def portal_root_url
    ENV.fetch("PORTAL_HOST", "https://portal.yagye.com")
  end

  def portal_url(path)
    host = ENV.fetch("PORTAL_HOST", "https://portal.yagye.com").delete_suffix("/")
    path.start_with?("http") ? path : "#{host}#{path}"
  end
end
