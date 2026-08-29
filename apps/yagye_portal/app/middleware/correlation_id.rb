# frozen_string_literal: true

# Thread-safe correlation ID accessor backed by RequestStore.
# Set by CorrelationIdMiddleware at the start of every HTTP request.
# Falls back to a generated ID so callers never receive nil.
module CorrelationId
  def self.current
    RequestStore.store[:correlation_id] ||= SecureRandom.hex(16)
  end

  def self.current=(value)
    RequestStore.store[:correlation_id] = value
  end

  def self.clear
    RequestStore.store.delete(:correlation_id)
  end
end
