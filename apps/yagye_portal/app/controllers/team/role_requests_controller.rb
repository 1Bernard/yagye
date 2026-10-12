# frozen_string_literal: true

module Team
  class RoleRequestsController < ApplicationController
    def index
      authorize RoleAssignmentRequest, :index?
      requests = policy_scope(RoleAssignmentRequest)
                   .pending
                   .includes(:target_user, :requested_by)
                   .recent
      role_keys = requests.flat_map { |r| r.current_role_keys + r.requested_role_keys }.uniq
      roles_by_key = Role.where(key: role_keys).index_by(&:key)
      render Team::RoleRequests::IndexView.new(requests: requests, roles_by_key: roles_by_key)
    end

    def approve_modal
      req = RoleAssignmentRequest.find(params[:id])
      authorize req, :approve?
      render UI::ConfirmModal.new(
        title:         "Approve role change",
        body:          "#{req.target_user.full_name}'s access permissions will update immediately.",
        confirm_path:  approve_team_role_request_path(req),
        confirm_label: "Approve change",
        success:       true
      )
    end

    def reject_modal
      req = RoleAssignmentRequest.find(params[:id])
      authorize req, :reject?
      render UI::ConfirmModal.new(
        title:         "Reject role change",
        body:          "The role change request for #{req.target_user.full_name} will be declined.",
        confirm_path:  reject_team_role_request_path(req),
        confirm_label: "Reject request",
        danger:        true
      )
    end

    def approve
      req = RoleAssignmentRequest.find(params[:id])
      authorize req, :approve?
      result = Team::ApproveRoleChange.new(request: req, approved_by: current_user).call
      if result.success?
        redirect_to team_role_requests_path,
                    notice: "Role change approved — #{req.target_user.full_name}'s access has been updated."
      else
        redirect_to team_role_requests_path, alert: result.error
      end
    end

    def reject
      req = RoleAssignmentRequest.find(params[:id])
      authorize req, :reject?
      result = Team::RejectRoleChange.new(request: req, rejected_by: current_user,
                                          reason: params[:rejection_reason]).call
      if result.success?
        redirect_to team_role_requests_path, notice: "Request rejected."
      else
        redirect_to team_role_requests_path, alert: result.error
      end
    end
  end
end
