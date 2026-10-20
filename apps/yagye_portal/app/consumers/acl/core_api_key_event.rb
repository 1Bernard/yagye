# frozen_string_literal: true

module Acl
  # Translates a raw Core API key event payload into Portal's model language.
  #
  # Core field  → Portal column   Reason
  # ----------    -------------   -------
  # public_id   → key_id          Portal uses key_id as the stable identifier
  # prefix      → key_prefix      Portal disambiguates from "prefix" which is a reserved word in some contexts
  # mode        → mode (mapped)   Core uses "sandbox"/"simulation"; Portal normalises both to "test"
  class CoreApiKeyEvent
    def initialize(payload)
      @p = payload
    end

    def valid?        = key_id.present?

    def key_id        = @p["key_id"] || @p["public_id"]
    def merchant_code = @p["merchant_code"]
    def label         = @p["label"] || ""
    def key_prefix    = @p["key_prefix"] || @p["prefix"] || ""
    def kind          = @p["kind"] || "secret"
    def scopes        = Array(@p["scopes"])
    def created_by    = @p["created_by"]
    def expires_at    = @p["expires_at"]
    def last_used_at  = @p["last_used_at"]
    def revoked_at    = @p["revoked_at"]
    def event_id      = @p["event_id"].to_s

    def mode
      case @p["mode"]
      when "sandbox", "simulation" then "test"
      when "live"                  then "live"
      else @p["mode"].presence || "test"
      end
    end

    def newly_created? = revoked_at.nil?
  end
end
