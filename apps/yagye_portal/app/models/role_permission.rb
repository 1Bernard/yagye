class RolePermission < ApplicationRecord
  self.primary_key = [:role_key, :permission_key]

  belongs_to :role, foreign_key: :role_key, primary_key: :key
  belongs_to :permission, foreign_key: :permission_key, primary_key: :key

  validates :role_key, :permission_key, :granted_at, presence: true
end
