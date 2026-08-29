class ApplicationController < ActionController::Base
  include Pundit::Authorization
  include Pagy::Method

  allow_browser versions: :modern
  stale_when_importmap_changes

  before_action :authenticate_user!
  before_action :set_current_user
  before_action :set_locale

  after_action :verify_authorized, unless: :devise_controller?

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  private

  def set_locale
    I18n.locale = session[:locale].presence_in(%w[en fr]) || I18n.default_locale
  end

  def set_current_user
    Current.user         = current_user
    Current.request_id   = request.request_id
    Current.ip_address   = request.remote_ip
    Current.user_agent   = request.user_agent
  end

  def user_not_authorized
    flash[:alert] = t("pundit.not_authorized")
    redirect_back_or_to root_path, status: :see_other
  end

  def not_implemented
    skip_authorization
    head :not_implemented
  end
end
