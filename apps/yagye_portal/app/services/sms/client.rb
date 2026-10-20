# frozen_string_literal: true

module Sms
  # Provider-agnostic SMS gateway. Resolves the adapter from
  # Rails.application.config.sms_adapter (set in config/initializers/sms.rb).
  # Swap providers by changing the initializer — no callers change.
  def self.send_sms(to:, content:, tag: nil)
    Rails.application.config.sms_adapter.send_sms(to:, content:, tag:)
  end
end
