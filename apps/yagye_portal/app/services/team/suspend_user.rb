# frozen_string_literal: true

module Team
  class SuspendUser
    Result = Struct.new(:success?, :error, keyword_init: true)

    def initialize(user:, suspended_by:)
      @user         = user
      @suspended_by = suspended_by
    end

    def call
      return Result.new(success?: false, error: "You cannot suspend yourself") if @user == @suspended_by

      User.transaction do
        @user.active_membership&.update!(state: "suspended")
        @user.lock_access!(send_instructions: false)
      end

      Result.new(success?: true)
    rescue => e
      Result.new(success?: false, error: e.message)
    end
  end
end
