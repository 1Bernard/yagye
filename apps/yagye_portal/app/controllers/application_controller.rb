class ApplicationController < ActionController::Base
  include Pundit::Authorization
  include Pagy::Method
  include PaperTrail::Rails::Controller

  allow_browser versions: :modern
  stale_when_importmap_changes

  before_action :authenticate_user!
  before_action :set_current_user
  before_action :set_locale
  before_action :set_paper_trail_whodunnit

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

  # Stamps lograge JSON lines with user/merchant context so log entries
  # can be joined to audit_logs by user_id or merchant_code.
  def append_info_to_payload(payload)
    super
    payload[:user_id]       = current_user&.id
    payload[:merchant_code] = current_user&.merchant_code
  end

  # PaperTrail — records the current user's email as the change author.
  def user_for_paper_trail
    current_user&.email
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
