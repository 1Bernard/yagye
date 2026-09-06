# frozen_string_literal: true

module Team
  class ApproveRoleChange
    include Auditable

    Result = Struct.new(:success?, :error, keyword_init: true)

    def initialize(request:, approved_by:)
      @request     = request
      @approved_by = approved_by
    end

    def call
      return Result.new(success?: false, error: "Request has already been decided") unless @request.pending?

      if @approved_by == @request.requested_by
        return Result.new(success?: false, error: "You cannot approve a request you submitted")
      end

      user = @request.target_user

      ActiveRecord::Base.transaction do
        current = user.user_roles.active.pluck(:role_key)

        (current - @request.requested_role_keys).each do |key|
          Team::RevokeRole.new(user: user, role_key: key, revoked_by: @approved_by).call
        end

        (@request.requested_role_keys - current).each do |key|
          Team::AssignRole.new(user: user, role_key: key, assigned_by: @approved_by).call
        end

        @request.update!(status: "approved", reviewed_by: @approved_by, reviewed_at: Time.current)
      end

      audit_log(action: "team.role_change_approved", resource_type: "User",
                resource_code: user.id, outcome: "succeeded",
                metadata: { added: @request.added_keys, removed: @request.removed_keys,
                             approved_by: @approved_by.id })
      Result.new(success?: true)
    rescue => e
      Result.new(success?: false, error: e.message)
    end
  end
end
