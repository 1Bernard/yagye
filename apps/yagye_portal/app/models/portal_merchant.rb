# frozen_string_literal: true

# Read model populated by Karafka consumers on merchant.* events from Core.
# Never written to directly from controllers or services — only consumers touch this.
class PortalMerchant < ApplicationRecord
  self.primary_key = "merchant_code"

  validates :merchant_code, presence: true

  def self.find_for(merchant_code)
    find_by(merchant_code: merchant_code)
  end
end
