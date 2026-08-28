class Permission < ApplicationRecord
  self.primary_key = :key

  has_many :role_permissions, foreign_key: :permission_key, primary_key: :key, dependent: :destroy
  has_many :roles, through: :role_permissions

  validates :key, :resource, :action, :description, presence: true
  validates :key, uniqueness: true
end
