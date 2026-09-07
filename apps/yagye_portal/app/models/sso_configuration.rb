# frozen_string_literal: true

class SsoConfiguration < ApplicationRecord
  validates :name, :email_domain, :idp_sso_target_url, :idp_cert, :merchant_code, presence: true
  validates :email_domain, uniqueness: { case_sensitive: false }

  before_save { self.email_domain = email_domain.downcase.strip }

  def self.active_for_email_domain?(email)
    domain = email.to_s.split("@").last.to_s.downcase.strip
    domain.present? && exists?(email_domain: domain, active: true)
  end

  def self.find_for_email(email)
    domain = email.to_s.split("@").last.to_s.downcase.strip
    find_by(email_domain: domain, active: true)
  end

  def self.find_for_domain(domain)
    find_by(email_domain: domain.to_s.downcase.strip, active: true)
  end
end
