class Role < ApplicationRecord
  self.primary_key = :key

  has_many :role_permissions, foreign_key: :role_key, primary_key: :key, dependent: :destroy
  has_many :permissions, through: :role_permissions
  has_many :user_roles, foreign_key: :role_key, primary_key: :key, dependent: :restrict_with_error

  validates :key, :name, :scope, :description, presence: true
  validates :scope, inclusion: { in: %w[merchant internal] }
  validates :key, uniqueness: true
end
