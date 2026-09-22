# frozen_string_literal: true

class PortalIpAllowlist < ApplicationRecord
  self.table_name = "portal_ip_allowlists"

  has_paper_trail

  validates :merchant_code, :cidr, presence: true
  validates :cidr, format: {
    with:    /\A(\d{1,3}\.){3}\d{1,3}(\/\d{1,2})?\z/,
    message: "must be a valid IPv4 address or CIDR (e.g. 192.168.1.1 or 10.0.0.0/24)"
  }

  scope :kept,         -> { where(deleted_at: nil) }
  scope :for_merchant, ->(code) { where(merchant_code: code) }

  def soft_delete!
    update!(deleted_at: Time.current)
  end
end
