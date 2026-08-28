class DashboardPolicy < ApplicationPolicy
  # All authenticated users may view the dashboard.
  # The content adapts based on their permission set.
  def index?
    user.present?
  end
end
