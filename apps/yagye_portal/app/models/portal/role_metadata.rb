# frozen_string_literal: true

module Portal
  # Single source for role display metadata (icon, palette, descriptive hint).
  # Roles themselves are DB-backed; this module provides the UI layer for each
  # known role key so views never hardcode parallel arrays.
  module RoleMetadata
    MERCHANT = [
      { key: "merchant_owner",     label: "Owner",     hint: "Full account access",            icon: :shield,   palette: "brand"  },
      { key: "merchant_finance",   label: "Finance",   hint: "Payouts, settlements & reports", icon: :wallet,   palette: "green"  },
      { key: "merchant_developer", label: "Developer", hint: "API keys, webhooks, event logs", icon: :key,      palette: "purple" },
      { key: "merchant_support",   label: "Support",   hint: "View payments and disputes",     icon: :headset,  palette: "teal"   }
    ].freeze

    INTERNAL = [
      { key: "ops_analyst",        label: "Ops Analyst",        hint: "Read-only operational access",   icon: :eye,          palette: "amber" },
      { key: "ops_manager",        label: "Ops Manager",        hint: "Operational access + approvals", icon: :settings,     palette: "amber" },
      { key: "compliance_analyst", label: "Compliance Analyst", hint: "KYB review, screening",          icon: :file,         palette: "red"   },
      { key: "compliance_manager", label: "Compliance Manager", hint: "Compliance review + overrides",  icon: :check_circle, palette: "red"   }
    ].freeze

    ALL = (MERCHANT + INTERNAL).freeze

    def self.for_key(key)    = ALL.find { |r| r[:key] == key.to_s }
    def self.icon_for(key)   = for_key(key)&.dig(:icon)    || :users
    def self.palette_for(key) = for_key(key)&.dig(:palette) || "brand"
    def self.hint_for(key)   = for_key(key)&.dig(:hint)    || ""
  end
end
