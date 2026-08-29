# frozen_string_literal: true

module Team
  class SuspendUser
    include Auditable

    Result = Struct.new(:success?, :error, keyword_init: true)

    def initialize(user:, suspended_by:, request: nil)
      @user         = user
      @suspended_by = suspended_by
      @request      = request
    end

    def call
      if @user == @suspended_by
        audit_log(action: "team.user_suspended", resource_type: "User",
                  resource_code: @user.id, outcome: "failed",
                  metadata: { reason: "cannot suspend self" })
        return Result.new(success?: false, error: "You cannot suspend yourself")
      end

      User.transaction do
        @user.active_membership&.update!(state: "suspended")
        @user.lock_access!(send_instructions: false)
      end

      audit_log(action: "team.user_suspended", resource_type: "User",
                resource_code: @user.id, outcome: "succeeded")
      Result.new(success?: true)
    rescue => e
      Result.new(success?: false, error: e.message)
    end
  end
end
