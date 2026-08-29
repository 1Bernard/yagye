# frozen_string_literal: true

module Team
  class UsersController < ApplicationController
    def index
      authorize User, :index?
      scope    = policy_scope(User)
      @users   = Team::UsersQuery.new(scope).call(filters)
      @can_invite = policy(User).invite?
    end

    def show
      @user = policy_scope(User).find(params[:id])
      authorize @user
      @roles       = @user.user_roles.includes(:role).where(revoked_at: nil).order(:created_at)
      @can_manage  = policy(@user).update?
      @can_suspend = policy(@user).destroy?
    end

    private

    def filters
      params.permit(:q, :role, :status).to_h.symbolize_keys
    end
  end
end
