# frozen_string_literal: true

module Team
  class RejectRoleChange
    include Auditable

    Result = Struct.new(:success?, :error, keyword_init: true)

    def initialize(request:, rejected_by:, reason: nil)
      @request     = request
      @rejected_by = rejected_by
      @reason      = reason.presence
    end

    def call
      return Result.new(success?: false, error: "Request has already been decided") unless @request.pending?

      if @rejected_by == @request.requested_by
        return Result.new(success?: false, error: "You cannot reject a request you submitted")
      end

      @request.update!(
        status:           "rejected",
        reviewed_by:      @rejected_by,
        reviewed_at:      Time.current,
        rejection_reason: @reason
      )

      audit_log(action: "team.role_change_rejected", resource_type: "User",
                resource_code: @request.target_user_id, outcome: "succeeded",
                metadata: { reason: @reason, rejected_by: @rejected_by.id })
      Result.new(success?: true)
    rescue => e
      Result.new(success?: false, error: e.message)
    end
  end
end
