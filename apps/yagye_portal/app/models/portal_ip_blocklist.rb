# frozen_string_literal: true

class PortalIpBlocklist < ApplicationRecord
  self.table_name = "portal_ip_blocklists"

  has_paper_trail

  REASONS = %w[fraud abuse dos_attack scraping other].freeze

  validates :merchant_code, :cidr, presence: true
  validates :cidr, format: {
    with:    /\A(\d{1,3}\.){3}\d{1,3}(\/\d{1,2})?\z/,
    message: "must be a valid IPv4 address or CIDR (e.g. 192.168.1.1 or 10.0.0.0/24)"
  }
  validates :cidr, uniqueness: {
    scope:      :merchant_code,
    conditions: -> { kept },
    message:    "is already in your IP blocklist"
  }
  validates :reason, inclusion: { in: REASONS }, allow_blank: true

  scope :kept,         -> { where(deleted_at: nil) }
  scope :for_merchant, ->(code) { where(merchant_code: code) }

  def soft_delete!
    update!(deleted_at: Time.current)
  end
end
