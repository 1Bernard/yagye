# frozen_string_literal: true

class NotificationsController < ApplicationController
  before_action :authenticate_user!

  # GET /notifications/:id/open — marks one notification as read, redirects to target
  def open
    notif = current_user.portal_notifications.find(params[:id])
    notif.mark_read!
    broadcast_badge_update

    redirect_to(notif.link.presence || authenticated_root_path, allow_other_host: false)
  end

  # PATCH /notifications/read-all
  def read_all
    current_user.portal_notifications.unread.update_all(read_at: Time.current)
    broadcast_badge_update

    redirect_to(request.referer || authenticated_root_path, status: :see_other)
  end

  private

  def broadcast_badge_update
    stream        = "user_notifications_#{current_user.id}"
    unread_count  = current_user.portal_notifications.unread.count
    badge_html    = render_to_string(
      partial: "notifications/badge",
      locals:  { unread_count: unread_count },
      layout:  false
    )
    Turbo::StreamsChannel.broadcast_replace_to(stream, target: "notif-bell", html: badge_html)
  rescue StandardError => e
    Rails.logger.warn("[NotificationsController] badge broadcast failed: #{e.message}")
  end
end
