class PortalMerchantApplication < ApplicationRecord
  self.primary_key = "application_code"

  STATUSES = %w[submitted under_review approved rejected].freeze

  scope :pending_review, -> { where(status: %w[submitted under_review]) }
  scope :by_status, ->(s) { where(status: s) }
  scope :recent, -> { order(last_applied_at: :desc) }

  def approved?
    status == "approved"
  end

  def rejected?
    status == "rejected"
  end

  def pending?
    status.in?(%w[submitted under_review])
  end

  def status_label
    status.humanize
  end
end
