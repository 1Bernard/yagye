# frozen_string_literal: true

module Team
  class RevokeRole
    include Auditable

    Result = Struct.new(:success?, :error, keyword_init: true)

    def initialize(user:, role_key:, revoked_by:, request: nil)
      @user       = user
      @role_key   = role_key
      @revoked_by = revoked_by
      @request    = request
    end

    def call
      user_role = @user.user_roles.find_by(role_key: @role_key, revoked_at: nil)
      unless user_role
        audit_log(action: "team.role_revoked", resource_type: "UserRole",
                  resource_code: @user.id, outcome: "failed",
                  metadata: { role_key: @role_key, reason: "not found" })
        return Result.new(success?: false, error: "Active role assignment not found")
      end

      user_role.revoke!(by: @revoked_by)
      audit_log(action: "team.role_revoked", resource_type: "UserRole",
                resource_code: @user.id, outcome: "succeeded",
                metadata: { role_key: @role_key })
      Result.new(success?: true)
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success?: false, error: e.message)
    end
  end
end
