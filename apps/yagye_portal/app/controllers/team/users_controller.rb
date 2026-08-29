# frozen_string_literal: true

module Team
  class UsersController < ApplicationController
    def index
      authorize User, :index?
      users = Team::UsersQuery.new(policy_scope(User)).call(filters)
      render Team::Users::IndexPage.new(
        users: users, can_invite: policy(User).invite?,
        query: params[:q], role: params[:role], status: params[:status]
      )
    end

    def show
      user = policy_scope(User).find(params[:id])
      authorize user
      roles = user.user_roles.includes(:role).where(revoked_at: nil).order(:created_at)
      render Team::Users::ShowPage.new(
        user: user, roles: roles,
        can_manage: policy(user).update?
      )
    end

    private

    def filters
      params.permit(:q, :role, :status).to_h.symbolize_keys
    end
  end
end
