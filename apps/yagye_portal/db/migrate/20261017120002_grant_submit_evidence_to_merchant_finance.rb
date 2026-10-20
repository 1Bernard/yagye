# frozen_string_literal: true

class GrantSubmitEvidenceToMerchantFinance < ActiveRecord::Migration[8.0]
  def up
    perm = Permission.find_by!(key: "disputes.submit_evidence")
    role = Role.find_by!(key: "merchant_finance")
    return if role.permissions.include?(perm)

    RolePermission.create!(role_key: role.key, permission_key: perm.key, granted_at: Time.current)
  end

  def down
    RolePermission.where(role_key: "merchant_finance", permission_key: "disputes.submit_evidence").delete_all
  end
end
