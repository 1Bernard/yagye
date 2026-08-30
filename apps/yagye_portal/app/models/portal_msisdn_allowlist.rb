# frozen_string_literal: true

class PortalMsisdnAllowlist < ApplicationRecord
  self.table_name = "portal_msisdn_allowlists"

  has_paper_trail

  validates :merchant_code, :msisdn, presence: true
  validates :msisdn, format: {
    with:    /\A\+?[0-9]{7,15}\z/,
    message: "must be a valid phone number (digits only, 7–15 characters)"
  }

  scope :for_merchant, ->(code) { where(merchant_code: code) }
end
