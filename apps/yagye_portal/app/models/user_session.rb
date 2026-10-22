# frozen_string_literal: true

class UserSession < ApplicationRecord
  belongs_to :user

  STAFF_TTL    = 12.hours
  MERCHANT_TTL = 30.days

  validates :session_token_digest, :device_fingerprint, :expires_at, presence: true
  validates :session_token_digest, uniqueness: true

  scope :active, -> { where(revoked_at: nil).where("expires_at > ?", Time.current) }

  def self.create_for(user:, raw_token:, request:)
    fingerprint = Digest::SHA256.hexdigest(
      "#{request.user_agent}|#{request.remote_ip}"
    )
    ttl = user.internal_staff? ? STAFF_TTL : MERCHANT_TTL

    create!(
      user:                 user,
      session_token_digest: Digest::SHA256.hexdigest(raw_token),
      device_fingerprint:   fingerprint,
      ip:                   request.remote_ip,
      user_agent_hash:      Digest::SHA256.hexdigest(request.user_agent.to_s),
      mfa_satisfied_at:     Time.current,
      expires_at:           Time.current + ttl,
      created_at:           Time.current
    )
  end

  def self.find_active_by_token(raw_token)
    digest = Digest::SHA256.hexdigest(raw_token)
    active.find_by(session_token_digest: digest)
  end

  def revoke!
    update!(revoked_at: Time.current)
  end

  def active?
    revoked_at.nil? && expires_at > Time.current
  end

  def device_label
    return "Unknown device" if ip.blank?
    ip
  end
end
