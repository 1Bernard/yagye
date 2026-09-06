module Team
  class RolesController < ApplicationController
    def index
      authorize Role, :index?
      render Team::Roles::IndexView.new(
        roles:      Role.includes(:permissions, :user_roles).order(:scope, :key),
        can_manage: policy(Role).create?
      )
    end

    def new
      role = Role.new
      authorize role
      render Team::Roles::FormView.new(
        role: role, permissions: all_permissions, mode: :new
      )
    end

    def create
      role = Role.new(role_params.merge(system_role: false))
      authorize role
      if role.save
        sync_permissions(role, params[:permission_keys])
        redirect_to team_roles_path, notice: "Role \"#{role.name}\" created."
      else
        render Team::Roles::FormView.new(
          role: role, permissions: all_permissions, mode: :new,
          errors: role.errors.full_messages
        ), status: :unprocessable_entity
      end
    end

    def edit
      role = Role.includes(:permissions).find(params[:key])
      authorize role
      render Team::Roles::FormView.new(
        role: role, permissions: all_permissions, mode: :edit
      )
    end

    def update
      role = Role.includes(:permissions).find(params[:key])
      authorize role
      attrs = role.system_role? ? role_params.except(:key, :scope) : role_params
      if role.update(attrs)
        sync_permissions(role, params[:permission_keys])
        redirect_to team_roles_path, notice: "Role \"#{role.name}\" updated."
      else
        render Team::Roles::FormView.new(
          role: role, permissions: all_permissions, mode: :edit,
          errors: role.errors.full_messages
        ), status: :unprocessable_entity
      end
    end

    def destroy
      role = Role.find(params[:key])
      authorize role
      role.destroy!
      redirect_to team_roles_path, notice: "Role \"#{role.name}\" deleted."
    end

    private

    def role_params
      params.permit(:key, :name, :scope, :description)
    end

    def all_permissions
      Permission.order(:resource, :action)
    end

    def sync_permissions(role, keys)
      requested = Array(keys).reject(&:blank?)
      current   = role.role_permissions.pluck(:permission_key)
      (current - requested).each { |k| role.role_permissions.find_by(permission_key: k)&.destroy }
      (requested - current).each do |k|
        role.role_permissions.create!(permission_key: k, granted_at: Time.current)
      end
    end
  end
end
