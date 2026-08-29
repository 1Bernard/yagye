module Team
  class RolesController < ApplicationController
    def index
      authorize Role, :index?
      render Team::Roles::IndexView.new(
        roles: Role.includes(:permissions, :user_roles).order(:scope, :key)
      )
    end
  end
end
