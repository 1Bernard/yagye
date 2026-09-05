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

    def show
      user = decode_id(User)
      authorize user
      roles = user.user_roles.includes(:role).where(revoked_at: nil).order(:created_at)
      render Team::Users::ShowView.new(
        user: user, roles: roles,
        can_manage: policy(user).update?
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
