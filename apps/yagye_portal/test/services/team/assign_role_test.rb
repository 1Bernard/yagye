# frozen_string_literal: true

require "test_helper"

module Team
  class AssignRoleTest < ActiveSupport::TestCase
    setup do
      @manager  = create(:internal_staff_user)
      @merchant = create(:merchant_user)
    end

    test "returns failure when the role key does not exist" do
      result = call(user: @merchant, role_key: "nonexistent_role", assigned_by: @manager)

      refute result.success?
      assert_equal "Role 'nonexistent_role' not found", result.error
    end

    test "merchant user cannot assign an internal role" do
      owner = create(:merchant_user)
      result = call(user: create(:merchant_user), role_key: "ops_analyst", assigned_by: owner)

      refute result.success?
      assert_equal "Merchant users cannot assign internal roles", result.error
    end

    test "returns failure if the user already holds the role" do
      create(:user_role, user: @merchant, role_key: "merchant_finance",
             merchant_code: @merchant.merchant_code)

      result = call(user: @merchant, role_key: "merchant_finance", assigned_by: @manager)

      refute result.success?
      assert_equal "User already has this role", result.error
    end

    test "creates a UserRole and returns it on success" do
      assert_difference "UserRole.count", 1 do
        result = call(user: @merchant, role_key: "merchant_finance", assigned_by: @manager)
        assert result.success?
        assert_equal "merchant_finance", result.user_role.role_key
        assert_equal @merchant,          result.user_role.user
      end
    end

    test "assigns internal role to internal_staff" do
      assert_difference "UserRole.count", 1 do
        result = call(user: @manager, role_key: "ops_analyst", assigned_by: @manager)
        assert result.success?
        assert_equal "ops_analyst", result.user_role.role_key
      end
    end

    test "newly assigned role is immediately returned by UserRole.active" do
      result = call(user: @merchant, role_key: "merchant_finance", assigned_by: @manager)
      assert_includes UserRole.active.where(user: @merchant, role_key: "merchant_finance"), result.user_role
    end

    private

    def call(user:, role_key:, assigned_by:, merchant_code: nil)
      Team::AssignRole.new(
        user:          user,
        role_key:      role_key,
        assigned_by:   assigned_by,
        merchant_code: merchant_code
      ).call
    end
  end
end
