# frozen_string_literal: true

# Composes and delivers transactional SMS messages via Brevo.
# All sends are fire-and-forget (enqueued via SmsNotifierJob).
#
# Usage:
#   SmsNotifier.payment_success(user: user, amount: "GHS 100.00", ref: "PAY-XXXXX")
#   SmsNotifier.reserve_policy_applied(user: user, merchant_name: "KofiBuild")
#   SmsNotifier.otp_code(to: "+233201234567", code: "481203")
class SmsNotifier
  # ── Payment events ────────────────────────────────────────────────────────

  def self.payment_success(user:, amount:, ref:)
    return unless sms_target?(user)
    enqueue(
      to:      user.phone_number,
      content: "Your Yagye payment of #{amount} was successful. Ref: #{ref}",
      tag:     "payment_success"
    )
  end

  def self.payment_failed(user:, amount:, ref:)
    return unless sms_target?(user)
    enqueue(
      to:      user.phone_number,
      content: "Your Yagye payment of #{amount} was not completed. Ref: #{ref}. Please try again or contact support.",
      tag:     "payment_failed"
    )
  end

  # ── Reserve / compliance events ───────────────────────────────────────────

  def self.reserve_policy_applied(user:, merchant_name:, auto_activates_on:)
    return unless sms_target?(user)
    enqueue(
      to:      user.phone_number,
      content: "Yagye: A reserve policy has been applied to #{merchant_name}. " \
               "Log in to the portal to review and acknowledge by #{auto_activates_on}.",
      tag:     "reserve_policy"
    )
  end

  # ── Auth events ───────────────────────────────────────────────────────────

  # Sends a 6-digit OTP code via SMS.
  # Caller is responsible for generating and storing the code before calling this.
  # Note: SMS OTP for auth is deferred; this exists for future wiring.
  def self.otp_code(to:, code:)
    Brevo::SmsClient.send_sms(
      to:      to,
      content: "#{code} is your Yagye sign-in code. It expires in 10 minutes. Do not share it.",
      tag:     "otp"
    )
  end

  # ── Generic notification ──────────────────────────────────────────────────

  def self.notify(to:, content:, tag: nil)
    enqueue(to:, content:, tag:)
  end

  private_class_method def self.sms_target?(user)
    user.phone_number.present? && user.notification_pref("channels", "sms")
  end

  private_class_method def self.enqueue(to:, content:, tag: nil)
    SmsNotifierJob.perform_later(to: to, content: content, tag: tag)
  end
end
