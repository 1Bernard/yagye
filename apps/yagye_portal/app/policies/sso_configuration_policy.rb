# frozen_string_literal: true

class SsoConfigurationPolicy < ApplicationPolicy
  def manage? = user.internal_staff?

  def show?
    user.internal_staff? || SsoConfiguration.active_for_email_domain?(user.email.to_s)
  end
end
