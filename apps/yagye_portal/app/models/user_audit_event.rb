# frozen_string_literal: true

class UserAuditEvent < ApplicationRecord
  belongs_to :user

  EVENTS = %w[
    signed_in signed_out
    password_changed
    totp_enabled totp_disabled
    profile_updated
    api_key_created api_key_revoked
    webhook_added webhook_removed
    ip_allowlisted ip_removed
    ip_blocked ip_unblocked
    msisdn_allowlisted msisdn_removed
    msisdn_blocked msisdn_unblocked
    session_revoked
  ].freeze

  validates :event_type, inclusion: { in: EVENTS }

  scope :recent, -> { order(created_at: :desc) }

  LABELS = {
    "signed_in"         => "Signed in",
    "signed_out"        => "Signed out",
    "password_changed"  => "Password changed",
    "totp_enabled"      => "2FA enabled",
    "totp_disabled"     => "2FA disabled",
    "profile_updated"   => "Profile updated",
    "api_key_created"   => "API key created",
    "api_key_revoked"   => "API key revoked",
    "webhook_added"     => "Webhook added",
    "webhook_removed"   => "Webhook removed",
    "ip_allowlisted"    => "IP address added",
    "ip_removed"        => "IP address removed",
    "ip_blocked"        => "IP address blocked",
    "ip_unblocked"      => "IP address unblocked",
    "msisdn_allowlisted" => "Phone number added to allowlist",
    "msisdn_removed"    => "Phone number removed from allowlist",
    "msisdn_blocked"    => "Phone number blocked",
    "msisdn_unblocked"  => "Phone number unblocked",
    "session_revoked"   => "Session revoked"
  }.freeze

  ICONS = {
    "signed_in"         => :check_circle,
    "signed_out"        => :logout,
    "password_changed"  => :lock,
    "totp_enabled"      => :shield,
    "totp_disabled"     => :shield,
    "profile_updated"   => :edit,
    "api_key_created"   => :key,
    "api_key_revoked"   => :key,
    "webhook_added"     => :link,
    "webhook_removed"   => :link,
    "ip_allowlisted"    => :globe,
    "ip_removed"        => :globe,
    "ip_blocked"        => :shield_off,
    "ip_unblocked"      => :shield,
    "msisdn_allowlisted" => :phone,
    "msisdn_removed"    => :phone,
    "msisdn_blocked"    => :shield_off,
    "msisdn_unblocked"  => :shield,
    "session_revoked"   => :x
  }.freeze

  def label
    LABELS.fetch(event_type, event_type.humanize)
  end

  def icon
    ICONS.fetch(event_type, :clock)
  end
end
