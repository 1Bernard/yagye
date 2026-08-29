# frozen_string_literal: true

module Team
  class AssignRole
    Result = Struct.new(:success?, :user_role, :error, keyword_init: true)

    def initialize(user:, role_key:, assigned_by:, merchant_code: nil)
      @user          = user
      @role_key      = role_key
      @assigned_by   = assigned_by
      @merchant_code = merchant_code || user.merchant_code
    end

    def call
      role = Role.find_by(key: @role_key)
      return Result.new(success?: false, error: "Role '#{@role_key}' not found") unless role

      if @assigned_by.merchant_user? && role.scope == "internal"
        return Result.new(success?: false, error: "Merchant users cannot assign internal roles")
      end

      if UserRole.exists?(user: @user, role_key: @role_key, revoked_at: nil)
        return Result.new(success?: false, error: "User already has this role")
      end

      user_role = UserRole.create!(
        user:          @user,
        role:          role,
        granted_at:    Time.current,
        granted_by:    @assigned_by,
        merchant_code: @merchant_code
      )

      Result.new(success?: true, user_role: user_role)
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success?: false, error: e.message)
    end
  end
end
