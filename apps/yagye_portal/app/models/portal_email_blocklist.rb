# frozen_string_literal: true

class PortalEmailBlocklist < ApplicationRecord
  self.table_name = "portal_email_blocklists"

  has_paper_trail

  REASONS = %w[fraud spam abuse other].freeze

  validates :merchant_code, :email, presence: true
  validates :email, format: {
    with:    URI::MailTo::EMAIL_REGEXP,
    message: "must be a valid email address"
  }
  validates :email, uniqueness: {
    scope:      :merchant_code,
    conditions: -> { kept },
    message:    "is already in your email blocklist"
  }
  validates :reason, inclusion: { in: REASONS }, allow_blank: true

  scope :kept,         -> { where(deleted_at: nil) }
  scope :for_merchant, ->(code) { where(merchant_code: code) }

  def soft_delete!
    update!(deleted_at: Time.current)
  end
end
