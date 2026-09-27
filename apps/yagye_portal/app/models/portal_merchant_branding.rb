# frozen_string_literal: true

class PortalMerchantBranding < ApplicationRecord
  self.table_name = "portal_merchant_brandings"

  has_one_attached :logo

  validates :merchant_code, presence: true, uniqueness: true
  validate  :logo_content_type, if: -> { logo.attached? }

  scope :for_merchant, ->(code) { find_by(merchant_code: code) }

  def self.find_or_initialize_for(merchant_code)
    find_or_initialize_by(merchant_code: merchant_code)
  end

  def logo_url
    return nil unless logo.attached?
    Rails.application.routes.url_helpers.rails_blob_url(logo, only_path: true)
  end

  private

  def logo_content_type
    return if logo.content_type.in?(%w[image/png image/jpeg image/jpg image/svg+xml image/webp])
    errors.add(:logo, "must be a PNG, JPEG, SVG or WebP image")
  end
end
