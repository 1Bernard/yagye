class MerchantMembership < ApplicationRecord
  belongs_to :user
  belongs_to :invited_by, class_name: "User", optional: true

  scope :active, -> { where(state: "active") }

  validates :merchant_code, :merchant_name, :state, presence: true
  validates :state, inclusion: { in: %w[invited active suspended removed] }

  def accept!
    update!(state: "active", accepted_at: Time.current, invitation_token_digest: nil)
  end
end
