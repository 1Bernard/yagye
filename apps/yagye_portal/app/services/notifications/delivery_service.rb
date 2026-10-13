# frozen_string_literal: true

module Notifications
  class DeliveryService
    STREAM_PREFIX = "user_notifications_"

    def self.deliver(merchant_code:, event_type:, title:, body:, link: nil, metadata: {})
      new(merchant_code:, event_type:, title:, body:, link:, metadata:).deliver
    end

    def initialize(merchant_code:, event_type:, title:, body:, link: nil, metadata: {})
      @merchant_code = merchant_code
      @event_type    = event_type.to_s
      @title         = title
      @body          = body
      @link          = link
      @metadata      = metadata
    end

    def deliver
      users_wanting_event.each do |user|
        notif = create_notification(user)
        broadcast_to_topbar(user, notif)
        deliver_email(user, notif) if email_enabled?(user)
        deliver_sms(user, notif)   if sms_enabled?(user)
      end
    rescue StandardError => e
      Rails.logger.error("[Notifications::DeliveryService] #{e.class}: #{e.message}")
    end

    private

    def users_wanting_event
      User
        .joins(:merchant_memberships)
        .where(merchant_memberships: { merchant_code: @merchant_code, state: "active" })
        .select { |u| u.notification_pref("events", @event_type) }
    end

    def create_notification(user)
      PortalNotification.create!(
        user:       user,
        event_type: @event_type,
        title:      @title,
        body:       @body,
        link:       @link,
        metadata:   @metadata
      )
    end

    def broadcast_to_topbar(user, notif)
      stream   = "#{STREAM_PREFIX}#{user.id}"
      unread   = PortalNotification.for_user(user).unread.count

      # Update the bell badge count
      badge_html = ApplicationController.render(
        partial:  "notifications/badge",
        locals:   { unread_count: unread },
        layout:   false
      )
      Turbo::StreamsChannel.broadcast_replace_to(stream, target: "notif-bell", html: badge_html)

      # Prepend the new row into the open dropdown list (no-op if not open)
      row_html = ApplicationController.render(
        partial:  "notifications/row",
        locals:   { notification: notif },
        layout:   false
      )
      Turbo::StreamsChannel.broadcast_prepend_to(stream, target: "notif-list", html: row_html)
    rescue StandardError => e
      Rails.logger.warn("[Notifications] broadcast failed: #{e.message}")
    end

    def deliver_email(user, notif)
      NotificationMailer.notification_email(user, notif).deliver_later
    rescue StandardError => e
      Rails.logger.warn("[Notifications] email failed for user #{user.id}: #{e.message}")
    end

    def deliver_sms(user, notif)
      return unless user.phone_number.present?
      content = "#{notif.title}: #{notif.body}".truncate(160)
      SmsNotifier.notify(to: user.phone_number, content: content, tag: @event_type)
    rescue StandardError => e
      Rails.logger.warn("[Notifications] SMS failed for user #{user.id}: #{e.message}")
    end

    def email_enabled?(user)
      user.notification_pref("channels", "email")
    end

    def sms_enabled?(user)
      user.phone_number.present? && user.notification_pref("channels", "sms")
    end
  end
end
