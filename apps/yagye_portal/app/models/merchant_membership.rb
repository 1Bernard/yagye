class MerchantMembership < ApplicationRecord
  belongs_to :user
  belongs_to :invited_by, class_name: "User", optional: true

  scope :active, -> { where(state: "active") }

  validates :merchant_code, :merchant_name, :state, presence: true
  validates :state, inclusion: { in: %w[invited active suspended removed] }

  # Look up a pending invitation by the raw token from the email link.
  # Stores SHA256(token) in invitation_token_digest for O(1) lookup without
  # exposing the raw token in the database.
  def self.find_by_invitation_token(raw_token)
    digest = Digest::SHA256.hexdigest(raw_token.to_s)
    find_by(invitation_token_digest: digest, state: "invited")
  end

  # Generate a URL-safe random token, store its digest, return the raw token
  # to embed in the invitation link.
  def self.generate_invitation_token!
    raw    = SecureRandom.urlsafe_base64(32)
    digest = Digest::SHA256.hexdigest(raw)
    [ raw, digest ]
  end

  def invitation_valid?
    state == "invited" &&
      invitation_token_digest.present? &&
      invitation_expires_at.present? &&
      invitation_expires_at > Time.current
  end

  def accept!
    update!(state: "active", accepted_at: Time.current, invitation_token_digest: nil)
  end
end
