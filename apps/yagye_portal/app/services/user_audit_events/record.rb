# frozen_string_literal: true

module UserAuditEvents
  class Record
    def self.call(user:, event_type:, request: nil, metadata: {})
      return unless user.is_a?(User)

      UserAuditEvent.create!(
        user:       user,
        event_type: event_type.to_s,
        ip_address: request&.remote_ip,
        user_agent: request&.user_agent,
        metadata:   metadata
      )
    rescue ActiveRecord::ActiveRecordError, ActiveRecord::StatementInvalid => e
      Rails.logger.warn "[UserAuditEvents::Record] Failed to log #{event_type}: #{e.message}"
    end
  end
end
