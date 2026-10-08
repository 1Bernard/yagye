# frozen_string_literal: true

module PortalAuditable
  extend ActiveSupport::Concern

  private

  def audit(action:, resource_type:, outcome:, resource_code: nil, reason: nil, metadata: {})
    AuditLog.record(
      actor:         current_user,
      action:        action,
      resource_type: resource_type,
      outcome:       outcome.to_s,
      resource_code: resource_code,
      merchant_code: current_user.merchant_code,
      reason:        reason,
      metadata:      metadata,
      request:       request
    )
  end
end
