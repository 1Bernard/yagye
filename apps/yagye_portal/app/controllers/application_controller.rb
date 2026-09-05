class ApplicationController < ActionController::Base
  include Pundit::Authorization
  include Pagy::Method
  include PaperTrail::Rails::Controller

  allow_browser versions: :modern
  stale_when_importmap_changes

  before_action :authenticate_user!
  before_action :set_current_user
  before_action :set_portal_mode
  before_action :set_locale
  before_action :set_paper_trail_whodunnit

  after_action :verify_authorized, unless: :devise_controller?

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  private

  def set_locale
    db_locale  = user_signed_in? ? current_user.language_preference.presence_in(%w[en fr]) : nil
    I18n.locale = db_locale || session[:locale].presence_in(%w[en fr]) || I18n.default_locale
  end

  def set_current_user
    Current.user         = current_user
    Current.request_id   = request.request_id
    Current.ip_address   = request.remote_ip
    Current.user_agent   = request.user_agent
  end

  # Ops/internal_staff users see all modes (Current.mode = nil → no mode scope).
  # Merchant users are mode-scoped: session defaults to "test" on first visit.
  def set_portal_mode
    return unless current_user

    if current_user.internal_staff?
      Current.mode = nil
    else
      Current.mode = session[:portal_mode].presence_in(%w[test live]) || "test"
      session[:portal_mode] = Current.mode
    end
  end

  # Stamps lograge JSON lines with user/merchant context so log entries
  # can be joined to audit_logs by user_id or merchant_code.
  def append_info_to_payload(payload)
    super
    payload[:merchant_code] = current_user&.merchant_code
  end

  # PaperTrail — records the current user's email as the change author.
  def user_for_paper_trail
    current_user&.email
  end

  # Log sign-in for the non-TOTP path; TOTP path is logged in Sessions::verify_otp.
  def after_sign_in_path_for(resource)
    UserAuditEvents::Record.call(user: resource, event_type: :signed_in, request: request)
    super
  end

  def user_not_authorized
    flash[:alert] = t("pundit.not_authorized")
    redirect_back_or_to root_path, status: :see_other
  end

  # Looks up a record by its primary key (UUID or string code) and verifies
  # merchant ownership. Raises RecordNotFound on missing or cross-merchant records.
  # Internal staff bypass the ownership check and see all records.
  def decode_id(model_class, param = params[:id])
    pk  = model_class.primary_key
    record = model_class.find_by(pk => param)
    raise ActiveRecord::RecordNotFound unless record
    raise ActiveRecord::RecordNotFound unless merchant_owns?(record)

    record
  end

  def merchant_owns?(record)
    return true if current_user.internal_staff?
    return true unless record.respond_to?(:merchant_code)

    record.merchant_code == current_user.merchant_code
  end

  def not_implemented
    skip_authorization
    head :not_implemented
  end
end
