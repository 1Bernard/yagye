# Stub controller for nav routes not yet implemented.
# Renders a simple "coming soon" shell so sidebar links don't 500.
class PlaceholderController < ApplicationController
  def show
    skip_authorization
    render Placeholder::ShowPage.new(section: action_name_label)
  end

  private

  def action_name_label
    request.path.delete_prefix("/").split("/").first.to_s.humanize
  end
end
