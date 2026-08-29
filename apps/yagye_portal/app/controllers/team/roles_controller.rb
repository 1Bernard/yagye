module Team
  class RolesController < ApplicationController
    def index
      authorize Role, :index?
      render Team::Roles::IndexPage.new(
        roles: Role.includes(:permissions, :user_roles).order(:scope, :key)
      )
    end
  end
end
