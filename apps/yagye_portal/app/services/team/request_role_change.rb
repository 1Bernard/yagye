# frozen_string_literal: true

module Team
  class RequestRoleChange
    include Auditable

    Result = Struct.new(:success?, :request, :error, keyword_init: true)

    def initialize(target_user:, requested_by:, requested_keys:, current_keys:)
      @target_user    = target_user
      @requested_by   = requested_by
      @requested_keys = Array(requested_keys).map(&:to_s).sort
      @current_keys   = Array(current_keys).map(&:to_s).sort
    end

    def call
      if @target_user == @requested_by
        return Result.new(success?: false, error: "You cannot modify your own roles")
      end

      if @requested_keys == @current_keys
        return Result.new(success?: false, error: "No changes to the current role assignment")
      end

      if RoleAssignmentRequest.pending.exists?(target_user: @target_user)
        return Result.new(success?: false,
                          error: "A role change request for #{@target_user.full_name} is already awaiting approval")
      end

      req = RoleAssignmentRequest.new(
        target_user:        @target_user,
        requested_by:       @requested_by,
        current_role_keys:  @current_keys,
        requested_role_keys: @requested_keys,
        status:             "pending"
      )

      if req.save
        audit_log(action: "team.role_change_requested", resource_type: "User",
                  resource_code: @target_user.id, outcome: "succeeded",
                  metadata: { added: req.added_keys, removed: req.removed_keys })
        Result.new(success?: true, request: req)
      else
        Result.new(success?: false, error: req.errors.full_messages.first)
      end
    end
  end
end
