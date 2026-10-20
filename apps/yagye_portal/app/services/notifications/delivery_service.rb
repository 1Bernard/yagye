# frozen_string_literal: true

module Notifications
  class DeliveryService
    STREAM_PREFIX  = "user_notifications_"
    VALID_URGENCIES = %w[critical warning info].freeze
    TOPBAR_LIMIT   = 50

    # Delivers synchronously — use only from DeliverNotificationJob.
    # Consumers should call .schedule instead.
    def self.deliver(merchant_code:, event_type:, title:, body:, link: nil, metadata: {},
                     mode: "live", urgency: "info", source_event_id: nil)
      new(
        merchant_code:   merchant_code,
        event_type:      event_type,
        title:           title,
        body:            body,
        link:            link,
        metadata:        metadata,
        mode:            mode,
        urgency:         urgency,
        source_event_id: source_event_id
      ).deliver
    end

    # Enqueues delivery on the :notifications queue, off the consumer thread.
    def self.schedule(merchant_code:, event_type:, title:, body:, link: nil, metadata: {},
                      mode: "live", urgency: "info", source_event_id: nil)
      Notifications::DeliverNotificationJob.perform_later(
        merchant_code:   merchant_code,
        event_type:      event_type,
        title:           title,
        body:            body,
        link:            link,
        metadata:        metadata,
        mode:            mode,
        urgency:         urgency,
        source_event_id: source_event_id
      )
    end

    def initialize(merchant_code:, event_type:, title:, body:, link: nil, metadata: {},
                   mode: "live", urgency: "info", source_event_id: nil)
      @merchant_code   = merchant_code
      @event_type      = event_type.to_s
      @title           = title
      @body            = body
      @link            = link
      @metadata        = metadata
      @mode            = mode.to_s
      @urgency         = VALID_URGENCIES.include?(urgency.to_s) ? urgency.to_s : "info"
      @source_event_id = source_event_id.presence
    end

    def deliver
      # Simulation/sandbox events must not land in live user inboxes.
      return unless @mode == "live"

      users_wanting_event.each do |user|
        notif = create_notification(user)
        next if notif.nil?

        broadcast_to_topbar(user, notif)
        # Critical notifications always trigger email regardless of channel preference.
        deliver_email(user, notif) if email_enabled?(user) || @urgency == "critical"
        deliver_sms(user, notif)   if sms_enabled?(user)
      end
    rescue StandardError => e
      Rails.logger.error("[Notifications::DeliveryService] #{e.class}: #{e.message}")
    end

    private

    # SQL-level filter — avoids loading all active members into Ruby.
    # Matches notification_pref("events", event_type): true unless explicitly set to false.
    def users_wanting_event
      User
        .joins(:merchant_memberships)
        .where(merchant_memberships: { merchant_code: @merchant_code, state: "active" })
        .where(
          "notification_preferences -> 'events' ->> ? IS DISTINCT FROM 'false'",
          @event_type
        )
    end

    def create_notification(user)
      return nil if PortalNotification.already_delivered?(
        user_id:         user.id,
        source_event_id: @source_event_id
      )

      PortalNotification.create!(
        user:            user,
        event_type:      @event_type,
        title:           @title,
        body:            @body,
        link:            @link,
        metadata:        @metadata,
        urgency:         @urgency,
        source_event_id: @source_event_id
      )
    rescue ActiveRecord::RecordNotUnique
      # Race condition: concurrent delivery for the same source_event_id — safe to skip.
      nil
    end

    def broadcast_to_topbar(user, notif)
      stream  = "#{STREAM_PREFIX}#{user.id}"
      unread  = PortalNotification.for_user(user).unread.count

      badge_html = ApplicationController.render(Notifications::BadgeComponent.new(unread_count: unread))
      Turbo::StreamsChannel.broadcast_replace_to(stream, target: "notif-bell", html: badge_html)

      row_html = ApplicationController.render(Notifications::RowComponent.new(notification: notif))
      Turbo::StreamsChannel.broadcast_prepend_to(stream, target: "notif-list", html: row_html)
    rescue StandardError => e
      Rails.logger.warn("[Notifications] broadcast failed: #{e.message}")
    end

    def deliver_email(user, notif)
      NotificationMailer.notification_email(user, notif).deliver_later
    rescue StandardError => e
      Rails.logger.warn("[Notifications] email failed for user #{user.id}: #{e.class}")
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
