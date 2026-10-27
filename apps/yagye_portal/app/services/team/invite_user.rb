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
        return Result.new(success?: false, error: "Merchant users cannot assign internal roles.")
      end

      if role.scope == "merchant" && @merchant_code.blank?
        return Result.new(success?: false,
                          error: "No merchant context — merchant invitations must be sent from within a merchant account.")
      end

      role.scope == "internal" ? invite_internal_staff(role) : invite_merchant_user(role)
    rescue ActiveRecord::RecordInvalid => e
      audit_log(action: "team.user_invited", resource_type: "User",
                merchant_code: @merchant_code, outcome: "failed",
                metadata: { error: e.message })
      Result.new(success?: false, error: e.message)
    end

    private

    def invite_merchant_user(role)
      raw_token, digest = MerchantMembership.generate_invitation_token!
      user = membership = nil

      User.transaction do
        existing = User.find_by(email: @email)
        if existing
          return Result.new(success?: false,
                            error: "#{@email} is already registered. Ask them to sign in or contact support.")
        end

        user = User.create!(
          email: @email, first_name: @first_name, last_name: @last_name,
          kind: "merchant_user", password: SecureRandom.hex(16)
        )
        UserRole.create!(
          user: user, role: role, granted_at: Time.current,
          granted_by: @invited_by, merchant_code: @merchant_code
        )
        membership = MerchantMembership.create!(
          user:                    user,
          merchant_code:           @merchant_code,
          merchant_name:           @merchant_name,
          state:                   "invited",
          invited_by:              @invited_by,
          invitation_token_digest: digest,
          invitation_expires_at:   7.days.from_now
        )
      end

      UserMailer.invitation_instructions(user, membership, raw_token).deliver_later
      audit_log(action: "team.user_invited", resource_type: "User",
                resource_code: user.id, merchant_code: @merchant_code, outcome: "succeeded")
      Result.new(success?: true, user: user)
    end

    def invite_internal_staff(role)
      raw_token, digest = User.generate_invitation_token!
      user = nil

      User.transaction do
        existing = User.find_by(email: @email)
        if existing
          return Result.new(success?: false,
                            error: "#{@email} is already registered. Ask them to sign in or contact support.")
        end

        user = User.create!(
          email:                   @email,
          first_name:              @first_name,
          last_name:               @last_name,
          kind:                    "internal_staff",
          password:                SecureRandom.hex(16),
          invited_by:              @invited_by,
          invitation_token_digest: digest,
          invitation_expires_at:   7.days.from_now
        )
        UserRole.create!(
          user: user, role: role, granted_at: Time.current, granted_by: @invited_by
        )
      end

      UserMailer.staff_invitation_instructions(user, @invited_by, raw_token, user.invitation_expires_at).deliver_later
      audit_log(action: "team.user_invited", resource_type: "User",
                resource_code: user.id, merchant_code: nil, outcome: "succeeded")
      Result.new(success?: true, user: user)
    end
  end
end
