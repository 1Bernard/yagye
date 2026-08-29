# frozen_string_literal: true

# Read model populated by Karafka consumers on api_key.* events from Core.
# Never written to directly — only consumers write here. Revocation is a
# command to Core; the consumer updates this record when Core confirms.
class PortalApiKey < ApplicationRecord
  self.primary_key = "key_id"

  scope :active,   -> { where(revoked_at: nil) }
  scope :revoked,  -> { where.not(revoked_at: nil) }
  scope :for_mode, ->(mode) { where(mode: mode) }

  def active?
    revoked_at.nil?
  end

  alias active active?
end
