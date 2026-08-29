# frozen_string_literal: true

# Include in service objects to get a convenient audit_log helper.
# The service must assign @actor and @request (request is optional).
#
# Example:
#   class Team::InviteUser
#     include Auditable
#     def call
#       result = do_work
#       audit_log(action: "team.user_invited", resource_type: "User",
#                 resource_code: result.user&.id, outcome: result.success? ? "succeeded" : "failed")
#       result
#     end
#   end
module Auditable
  def audit_log(action:, resource_type:, outcome:, **kwargs)
    AuditLog.record(
      actor:         @actor || @invited_by || @assigned_by || @revoked_by ||
                     @suspended_by || @approved_by || @rejected_by || @created_by,
      action:        action,
      resource_type: resource_type,
      outcome:       outcome,
      request:       @request,
      **kwargs
    )
  end
end
