class DashboardController < ApplicationController
  def index
    authorize :dashboard, :index?
  end
end
