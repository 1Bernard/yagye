# frozen_string_literal: true

class AddDisputesApproveEvidencePermission < ActiveRecord::Migration[8.0]
  def up
    perm = Permission.create!(
      key:         "disputes.approve_evidence",
      resource:    "disputes",
      action:      "approve_evidence",
      description: "Review and approve drafted evidence before it is submitted to the network."
    )

    Role.where(key: "merchant_owner").each do |role|
      unless role.permissions.include?(perm)
        RolePermission.create!(role_key: role.key, permission_key: perm.key, granted_at: Time.current)
      end
    end
  end

  def down
    perm = Permission.find_by(key: "disputes.approve_evidence")
    return unless perm

    perm.role_permissions.delete_all
    perm.destroy!
  end
end
