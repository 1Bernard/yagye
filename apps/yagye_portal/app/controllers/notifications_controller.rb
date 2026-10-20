# frozen_string_literal: true

class NotificationsController < ApplicationController
  before_action :authenticate_user!

  PER_PAGE = 30

  # GET /notifications — paginated full notification list
  def index
    skip_authorization
    scope = current_user.portal_notifications.recent.limit(PER_PAGE + 1)

    if params[:before_created_at].present? && params[:before_id].present?
      scope = scope.where(
        "(created_at < :ts OR (created_at = :ts AND id::text < :id))",
        ts: params[:before_created_at],
        id: params[:before_id]
      )
    end

    records        = scope.to_a
    has_next       = records.length > PER_PAGE
    notifications  = records.first(PER_PAGE)
    next_cursor    = has_next ? { created_at: notifications.last.created_at.iso8601(6), id: notifications.last.id } : nil

    render Notifications::IndexView.new(notifications: notifications, next_cursor: next_cursor)
  end

  # GET /notifications/:id/open — marks one notification as read, redirects to target
  def open
    skip_authorization
    notif = current_user.portal_notifications.find(params[:id])
    notif.mark_read!
    broadcast_badge_update

    redirect_to(notif.link.presence || authenticated_root_path, allow_other_host: false)
  end

  # PATCH /notifications/read-all
  def read_all
    skip_authorization
    current_user.portal_notifications.unread.update_all(read_at: Time.current)
    broadcast_badge_update

    redirect_to(request.referer || authenticated_root_path, status: :see_other)
  end

  private

  def broadcast_badge_update
    stream        = "user_notifications_#{current_user.id}"
    unread_count  = current_user.portal_notifications.unread.count
    badge_html    = render_to_string(Notifications::BadgeComponent.new(unread_count: unread_count))
    Turbo::StreamsChannel.broadcast_replace_to(stream, target: "notif-bell", html: badge_html)
  rescue StandardError => e
    Rails.logger.warn("[NotificationsController] badge broadcast failed: #{e.message}")
  end
end
