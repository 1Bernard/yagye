class UserRole < ApplicationRecord
  belongs_to :user
  belongs_to :role, foreign_key: :role_key, primary_key: :key
  belongs_to :granted_by, class_name: "User", optional: true

  scope :active, -> {
    where(revoked_at: nil)
      .where("expires_at IS NULL OR expires_at > ?", Time.current)
  }

  validates :role_key, :granted_at, presence: true
  validate :scope_matches_user_kind, on: :create

  def revoke!(by: nil)
    update!(revoked_at: Time.current, granted_by: by || granted_by)
  end

  private

  def scope_matches_user_kind
    return unless role && user

    if role.scope == "merchant" && !user.merchant_user?
      errors.add(:role_key, "is a merchant role but user is internal_staff")
    elsif role.scope == "internal" && !user.internal_staff?
      errors.add(:role_key, "is an internal role but user is merchant_user")
    end
  end
end
