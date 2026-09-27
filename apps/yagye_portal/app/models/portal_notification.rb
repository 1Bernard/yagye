# frozen_string_literal: true

class PortalNotification < ApplicationRecord
  belongs_to :user

  scope :unread,  -> { where(read_at: nil) }
  scope :recent,  -> { order(created_at: :desc) }
  scope :for_user, ->(user) { where(user: user) }

  def read?
    read_at.present?
  end

  def mark_read!
    update!(read_at: Time.current) unless read?
  end
end
