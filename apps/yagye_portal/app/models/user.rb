class User < ApplicationRecord
  devise :database_authenticatable,
         :two_factor_authenticatable,
         :recoverable,
         :rememberable,
         :validatable,
         :trackable,
         :lockable,
         :timeoutable

  encrypts :otp_secret

  before_create :generate_user_code

  has_many :user_roles, dependent: :destroy
  has_many :active_user_roles, -> { active }, class_name: "UserRole"
  has_many :roles, through: :active_user_roles
  has_many :merchant_memberships, dependent: :destroy
  has_one :active_membership, -> { active }, class_name: "MerchantMembership"

  validates :kind, inclusion: { in: %w[merchant_user internal_staff] }

  def full_name
    [ first_name, last_name ].compact.join(" ").presence || email
  end

  def internal_staff?
    kind == "internal_staff"
  end

  def merchant_user?
    kind == "merchant_user"
  end

  # Dynamic permission check.
  # Results are cached per-request in Current.permissions (a Set).
  # Cost: 1 SQL query on first call, zero thereafter for that request.
  def permitted?(permission_key)
    permissions_cache.include?(permission_key.to_s)
  end

  def merchant_code
    active_membership&.merchant_code
  end

  private

  def permissions_cache
    Current.permissions ||= load_permissions_set
  end

  def load_permissions_set
    Set.new(
      UserRole.active.where(user_id: id)
        .joins(role: :role_permissions)
        .pluck("role_permissions.permission_key")
    )
  end

  def generate_user_code
    loop do
      code = "USR-#{SecureRandom.alphanumeric(8).upcase}"
      unless User.exists?(user_code: code)
        self.user_code = code
        break
      end
    end
  end
end
