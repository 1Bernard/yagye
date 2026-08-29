# frozen_string_literal: true

module Team
  class InviteUser
    include Auditable

    Result = Struct.new(:success?, :user, :error, keyword_init: true)

    def initialize(email:, first_name:, last_name:, role_key:,
                   merchant_code:, merchant_name:, invited_by:, request: nil)
      @email         = email.strip.downcase
      @first_name    = first_name.strip
      @last_name     = last_name.strip
      @role_key      = role_key
      @merchant_code = merchant_code
      @merchant_name = merchant_name
      @invited_by    = invited_by
      @request       = request
    end

    def call
      role = Role.find_by(key: @role_key)
      return Result.new(success?: false, error: "Role '#{@role_key}' not found") unless role

      if @invited_by.merchant_user? && role.scope == "internal"
        return Result.new(success?: false, error: "Merchant users cannot assign internal roles")
      end

      user = nil
      User.transaction do
        user = User.create!(
          email:      @email,
          first_name: @first_name,
          last_name:  @last_name,
          kind:       "merchant_user",
          password:   SecureRandom.hex(16)
        )
        UserRole.create!(
          user:          user,
          role:          role,
          granted_at:    Time.current,
          granted_by:    @invited_by,
          merchant_code: @merchant_code
        )
        MerchantMembership.create!(
          user:                   user,
          merchant_code:          @merchant_code,
          merchant_name:          @merchant_name,
          state:                  "invited",
          invited_by:             @invited_by,
          invitation_expires_at:  7.days.from_now
        )
      end

      # TODO P13: enqueue UserMailer::invitation_instructions

      audit_log(action: "team.user_invited", resource_type: "User",
                resource_code: user.id, merchant_code: @merchant_code, outcome: "succeeded")
      Result.new(success?: true, user: user)
    rescue ActiveRecord::RecordInvalid => e
      audit_log(action: "team.user_invited", resource_type: "User",
                merchant_code: @merchant_code, outcome: "failed",
                metadata: { error: e.message })
      Result.new(success?: false, error: e.message)
    end
  end
end
