# frozen_string_literal: true

module Team
  class RevokeRole
    Result = Struct.new(:success?, :error, keyword_init: true)

    def initialize(user:, role_key:, revoked_by:)
      @user       = user
      @role_key   = role_key
      @revoked_by = revoked_by
    end

    def call
      user_role = @user.user_roles.find_by(role_key: @role_key, revoked_at: nil)
      return Result.new(success?: false, error: "Active role assignment not found") unless user_role

      user_role.revoke!(by: @revoked_by)
      Result.new(success?: true)
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success?: false, error: e.message)
    end
  end
end
