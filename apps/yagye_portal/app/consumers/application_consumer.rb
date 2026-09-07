# frozen_string_literal: true

class ApplicationConsumer < Karafka::BaseConsumer
  # Errors that indicate bad/unprocessable message data — not transient failures.
  # These are logged and skipped immediately; Karafka will not retry them.
  SKIP_ERRORS = [
    ActiveRecord::RecordInvalid,
    ActiveRecord::SerializationTypeMismatch,
    JSON::ParserError
  ].freeze

  # Subclasses must implement #consume.
  # Do NOT rescue StandardError broadly — let unexpected failures propagate
  # so Karafka can retry them and ultimately route to the DLQ.
  # Only rescue SKIP_ERRORS when the message itself is unprocessable.

  def self.skip_error?(error)
    SKIP_ERRORS.any? { |klass| error.is_a?(klass) }
  end
end
