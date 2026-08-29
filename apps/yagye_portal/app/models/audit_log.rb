# frozen_string_literal: true

class AuditLog < ApplicationRecord
  belongs_to :user, optional: true

  OUTCOMES = %w[attempted succeeded failed].freeze

  validates :user_code,     presence: true
  validates :action,        presence: true
  validates :resource_type, presence: true
  validates :outcome,       inclusion: { in: OUTCOMES }

  # Primary entry point for all service objects and controllers.
  # Never raises — a logging failure must not abort the business operation.
  def self.record(actor:, action:, resource_type:, outcome:,
                  resource_code: nil, merchant_code: nil,
                  reason: nil, metadata: {}, request: nil)
    log_attrs = {
      user_id:       actor&.id,
      user_code:     actor&.email.to_s,
      merchant_code: merchant_code || actor&.merchant_code,
      action:        action,
      resource_type: resource_type.to_s,
      resource_code: resource_code.to_s.presence,
      outcome:       outcome.to_s,
      reason:        reason,
      metadata:      metadata,
      correlation_id: CorrelationId.current,
      ip:            request&.remote_ip,
      user_agent_hash: request ? Digest::SHA256.hexdigest(request.user_agent.to_s) : nil
    }

    create!(log_attrs)
  rescue => e
    Rails.logger.error("AuditLog.record failed: #{e.class} — #{e.message}")
    nil
  end
end
