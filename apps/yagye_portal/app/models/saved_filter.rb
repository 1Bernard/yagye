# frozen_string_literal: true

class SavedFilter < ApplicationRecord
  belongs_to :user

  NAMESPACES = %w[Payments Settlements Payouts Disputes].freeze

  validates :namespace, inclusion: { in: NAMESPACES }
  validates :name, presence: true, length: { maximum: 80 }
  validates :filters, presence: true

  scope :for_user, ->(user) { where(user: user) }
  scope :shared, -> { where(shared_with_merchant: true) }

  def self.visible_to(user)
    merchant_shared = user.merchant_code.present? ?
      joins(:user).where(shared_with_merchant: true,
                         users: { id: User.where.not(id: user.id)
                                         .joins(:merchant_memberships)
                                         .where(merchant_memberships: { merchant_code: user.merchant_code, state: "active" }) }) :
      none

    where(user: user).or(merchant_shared)
  end
end
