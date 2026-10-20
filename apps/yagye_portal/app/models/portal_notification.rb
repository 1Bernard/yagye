# frozen_string_literal: true

class PortalNotification < ApplicationRecord
  belongs_to :user

  URGENCIES = %w[critical warning info].freeze

  scope :unread,    -> { where(read_at: nil) }
  scope :recent,    -> { order(created_at: :desc, id: :desc) }
  scope :for_user,  ->(user) { where(user: user) }
  scope :critical,  -> { where(urgency: "critical") }
  scope :warning,   -> { where(urgency: "warning") }
  scope :info,      -> { where(urgency: "info") }

  validates :urgency, inclusion: { in: URGENCIES }

  def read?
    read_at.present?
  end

  def mark_read!
    update!(read_at: Time.current) unless read?
  end

  # Returns true when a notification for this (user, source_event_id) pair has already
  # been persisted. Prevents duplicate delivery when a consumer replays an event.
  def self.already_delivered?(user_id:, source_event_id:)
    return false if source_event_id.blank?

    where(user_id: user_id, source_event_id: source_event_id).exists?
  end
end
