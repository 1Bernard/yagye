# frozen_string_literal: true

module Team
  class UsersController < ApplicationController
    def index
      authorize User, :index?
      users = Team::UsersQuery.new(policy_scope(User)).call(filters)
      render Team::Users::IndexView.new(
        users: users, can_invite: policy(User).invite?,
        query: params[:q], role: params[:role], status: params[:status],
        view: params.fetch(:view, "list")
      )
    end

    def filter
      authorize User, :index?
      render Team::Users::FilterView.new(query: params[:q], role: params[:role], status: params[:status])
    end

    def show
      user = decode_id(User)
      authorize user
      roles           = user.user_roles.includes(:role).where(revoked_at: nil).order(:created_at)
      scope           = user.internal_staff? ? "internal" : "merchant"
      available_roles = Role.where(scope: scope).order(:name)
      audit_events    = UserAuditEvent.where(user: user).recent.limit(15)
      pending_request = RoleAssignmentRequest.pending.find_by(target_user: user)
      render Team::Users::ShowView.new(
        user: user, roles: roles,
        can_manage:      policy(user).update?,
        available_roles: available_roles,
        audit_events:    audit_events,
        pending_request: pending_request
      )
    end

    def new
      authorize User, :invite?
      render Team::Users::InviteView.new
    end

    def edit_roles
      user = decode_id(User)
      authorize user, :update?
      if user == current_user
        redirect_to team_user_path(user), alert: "You cannot modify your own roles."
        return
      end
      if RoleAssignmentRequest.pending.exists?(target_user: user)
        redirect_to team_user_path(user),
                    alert: "A role change request for #{user.full_name} is already awaiting approval."
        return
      end
      scope           = user.internal_staff? ? "internal" : "merchant"
      available_roles = Role.where(scope: scope).includes(:permissions).order(:name)
      current_keys    = user.user_roles.active.pluck(:role_key)
      render Team::Users::EditRolesView.new(
        user:            user,
        available_roles: available_roles,
        current_keys:    current_keys
      )
    end

    def create
      authorize User, :invite?
      result = Team::InviteUser.new(
        email:         invite_params[:email],
        first_name:    invite_params[:first_name],
        last_name:     invite_params[:last_name],
        role_key:      invite_params[:role_key],
        merchant_code: current_merchant_code,
        merchant_name: current_merchant_name,
        invited_by:    current_user,
        request:       request
      ).call
      if result.success?
        redirect_to team_users_path, notice: "Invitation sent to #{invite_params[:email]}."
      else
        redirect_to team_users_path, alert: result.error
      end
    end

    def suspend
      user = decode_id(User)
      authorize user, :suspend?
      result = Team::SuspendUser.new(user: user, suspended_by: current_user, request: request).call
      if result.success?
        redirect_to team_user_path(user), notice: "#{user.full_name} has been suspended."
      else
        redirect_to team_user_path(user), alert: result.error
      end
    end

    def set_roles
      user = decode_id(User)
      authorize user, :update?
      if user == current_user
        redirect_to team_user_path(user), alert: "You cannot modify your own roles."
        return
      end
      requested = Array(params[:role_keys]).reject(&:blank?)
      current   = user.user_roles.active.pluck(:role_key)
      result = Team::RequestRoleChange.new(
        target_user:    user,
        requested_by:   current_user,
        requested_keys: requested,
        current_keys:   current
      ).call
      if result.success?
        redirect_to team_role_requests_path,
                    notice: "Role change request submitted for #{user.full_name} — pending a second approver."
      else
        redirect_to team_user_path(user), alert: result.error
      end
    end

    def assign_role
      user = decode_id(User)
      authorize user, :update?
      result = Team::AssignRole.new(
        user:          user,
        role_key:      params[:role_key],
        assigned_by:   current_user,
        merchant_code: current_merchant_code
      ).call
      if result.success?
        redirect_to team_user_path(user), notice: "Role assigned."
      else
        redirect_to team_user_path(user), alert: result.error
      end
    end

    private

    def filters
      params.permit(:q, :role, :status).to_h.symbolize_keys
    end

    def invite_params
      params.permit(:email, :first_name, :last_name, :role_key)
    end

    def current_merchant_code
      current_user.merchant_code
    end

    def current_merchant_name
      current_user.active_membership&.merchant_name || current_merchant_code
    end
  end
end
