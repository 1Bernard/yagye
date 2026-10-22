class ApplicationController < ActionController::Base
  include Pundit::Authorization
  include Pagy::Method
  include PaperTrail::Rails::Controller
  include PortalAuditable

  allow_browser versions: :modern
  stale_when_importmap_changes

  before_action :authenticate_user!
  before_action :verify_user_session
  before_action :set_current_user
  before_action :set_portal_mode
  before_action :set_locale
  before_action :set_paper_trail_whodunnit
  before_action :load_kyb_banner_progress

  helper_method :kyb_banner_progress

  after_action :verify_authorized, unless: :devise_controller?

  rescue_from Pundit::NotAuthorizedError,          with: :user_not_authorized
  rescue_from ActionController::InvalidAuthenticityToken, with: :handle_csrf_expiry

  # Enforces DB-backed session validity. A revoked or expired session token
  # results in an immediate sign-out, even if Devise's cookie is still valid.
  # Skipped for Devise controllers (sign-in, OTP challenge, etc.).
  def verify_user_session
    return unless user_signed_in? && !devise_controller?

    raw_token = session[:user_session_token]
    return unless raw_token.present?

    unless UserSession.find_active_by_token(raw_token)
      session.delete(:user_session_token)
      sign_out current_user
      redirect_to new_user_session_path, alert: "Your session has expired or been revoked. Please sign in again.",
                  status: :see_other
    end
  end

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
    payload[:user_id]       = current_user&.id
    payload[:mode]          = Current.mode
  end

  # PaperTrail — records the current user's email as the change author.
  def user_for_paper_trail
    current_user&.email
  end

  def after_sign_in_path_for(resource)
    UserAuditEvents::Record.call(user: resource, event_type: :signed_in, request: request)
    super
  end

  def user_not_authorized
    if request.headers["Turbo-Frame"].present?
      render Shared::NotAuthorizedFrameComponent.new(frame_id: request.headers["Turbo-Frame"]),
             layout: false, status: :forbidden
    else
      flash[:alert] = t("pundit.not_authorized")
      redirect_back_or_to root_path, status: :see_other
    end
  end

  # CSRF token mismatch — most likely the session expired (Devise timeoutable
  # resets the session, invalidating the token embedded in the open page).
  # A full redirect to sign_in with 303 tells Turbo Drive to do a top-level
  # GET navigation, clearing the stale page state entirely.
  def handle_csrf_expiry
    sign_out current_user if user_signed_in?
    redirect_to new_user_session_path, status: :see_other,
                alert: "Your session expired. Please sign in again."
  end

  # Looks up a record by its primary key (UUID or string code) and verifies
  # merchant ownership. Raises RecordNotFound on missing or cross-merchant records.
  # Internal staff bypass the ownership check and see all records.
  def find_owned!(model_class, param = params[:id])
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

  def load_kyb_banner_progress
    return unless current_user&.merchant_user?

    cached = session[:kyb_progress_cache]
    if cached && Time.at(cached["at"].to_i) > 5.minutes.ago
      @_kyb_banner_progress = KybProgress.new(cached["data"] || {})
      return
    end

    result = CoreApiClient.new.get_kyb_status(current_user.merchant_code)
    return if result.error_code == "network_error"

    data = result.success? ? result.body : {}
    session[:kyb_progress_cache] = { "data" => data, "at" => Time.current.to_i }
    @_kyb_banner_progress = KybProgress.new(data)
  rescue StandardError
    # Silently suppress — a missing banner is less harmful than a broken page.
  end

  def kyb_banner_progress = @_kyb_banner_progress

  def invalidate_kyb_banner_cache
    session.delete(:kyb_progress_cache)
  end
end
