# frozen_string_literal: true

module Notifications
  # Deletes read portal_notifications older than 90 days.
  # Unread notifications are kept indefinitely so users never miss an alert.
  class PruneNotificationsJob < ApplicationJob
    queue_as :background

    def perform
      cutoff  = 90.days.ago
      deleted = PortalNotification
                  .where("read_at IS NOT NULL AND created_at < ?", cutoff)
                  .delete_all
      Rails.logger.info(
        "[Notifications::PruneNotificationsJob] Pruned #{deleted} read portal_notifications older than 90 days"
      )
    end
  end
end
