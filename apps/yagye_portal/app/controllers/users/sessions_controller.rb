class Users::SessionsController < Devise::SessionsController
  prepend_before_action :handle_two_factor_challenge, only: :create

  skip_before_action :authenticate_user!, only: %i[new otp_challenge verify_otp request_email_otp totp_enrollment complete_totp_enrollment]
  skip_after_action  :verify_authorized,  only: %i[new otp_challenge verify_otp request_email_otp totp_enrollment complete_totp_enrollment]

  def new
    self.resource = resource_class.new
    render Auth::SignInView.new(resource: resource, csrf_token: form_authenticity_token)
  end

  # GET /users/otp-challenge
  def otp_challenge
    resource = pending_otp_user
    redirect_to(new_user_session_path) and return unless resource
    render Auth::OtpView.new(
      csrf_token: form_authenticity_token,
      via_email:  session[:otp_via_email],
      user_email: resource.email
    )
  end

  # POST /users/otp-challenge
  def verify_otp
    user = pending_otp_user
    unless user
      redirect_to new_user_session_path, alert: "Session expired. Please sign in again."
      return
    end

    via_email = session[:otp_via_email]
    result    = if via_email
                  user.verify_email_otp!(submitted_otp)
    else
                  user.validate_and_consume_otp!(submitted_otp)
    end

    if result == :locked
      UserAuditEvents::Record.call(user: user, event_type: :email_otp_locked, request: request)
      session.delete(:otp_user_id)
      session.delete(:otp_via_email)
      redirect_to new_user_session_path,
        alert: "Too many incorrect attempts. Please sign in again to receive a new code."
      return
    end

    if result == true
      session.delete(:otp_user_id)
      session.delete(:otp_via_email)
      sign_in(:user, user)
      if via_email
        UserAuditEvents::Record.call(user: user, event_type: :email_otp_verified, request: request)
        OtpMailer.sign_in_alert(user: user, ip: request.remote_ip, time: Time.current).deliver_later
      else
        UserAuditEvents::Record.call(user: user, event_type: :signed_in, request: request)
      end
      redirect_to after_sign_in_path_for(user)
    else
      UserAuditEvents::Record.call(user: user, event_type: :email_otp_failed, request: request) if via_email
      flash.now[:alert] = via_email ?
        "Invalid or expired code. Check your email and try again." :
        "Invalid authentication code. Check your authenticator app and try again."
      render Auth::OtpView.new(
        csrf_token: form_authenticity_token,
        via_email:  via_email,
        user_email: user.email
      ), status: :unprocessable_entity
    end
  end

  # GET /users/totp-enrollment
  # Shown to internal_staff users who have no TOTP yet.
  # They must complete enrollment before being signed in.
  def totp_enrollment
    redirect_to(authenticated_root_path) and return if user_signed_in?
    user = pending_totp_setup_user
    redirect_to(new_user_session_path) and return unless user
    response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate"

    secret = session[:pending_otp_secret] ||= User.generate_otp_secret
    totp   = ROTP::TOTP.new(secret, issuer: "Yagye")
    uri    = totp.provisioning_uri(user.email)
    qr     = RQRCode::QRCode.new(uri)
    svg    = qr.as_svg(
      module_size: 4, shape_rendering: "crispEdges",
      module_color: "#1f2937", background_color: "#ffffff",
      standalone: true, use_path: true
    )

    render Auth::TotpEnrollmentView.new(
      csrf_token: form_authenticity_token,
      otp_secret: secret,
      qr_svg:     svg.html_safe,
      user_email: user.email
    )
  end

  # POST /users/totp-enrollment
  def complete_totp_enrollment
    user = pending_totp_setup_user
    redirect_to(new_user_session_path) and return unless user

    secret = session[:pending_otp_secret]
    unless secret.present?
      redirect_to users_totp_enrollment_path, alert: "Setup session expired. Please sign in again."
      return
    end

    totp = ROTP::TOTP.new(secret, issuer: "Yagye")
    unless totp.verify(params[:otp_code].to_s.gsub(/\s+/, ""), drift_behind: 15, drift_ahead: 15)
      redirect_to users_totp_enrollment_path, alert: "Invalid code. Make sure your authenticator is showing the current code and try again."
      return
    end

    user.update!(otp_secret: secret, otp_required_for_login: true)
    plain_codes = user.generate_recovery_codes!

    session.delete(:totp_setup_user_id)
    session.delete(:pending_otp_secret)

    UserAuditEvents::Record.call(user: user, event_type: :totp_enabled, request: request)
    sign_in(:user, user)

    # Store codes in session briefly so we can show them once after sign-in
    session[:totp_just_enrolled_codes] = plain_codes

    redirect_to settings_totp_recovery_codes_path, notice: "Two-factor authentication is now active. Save these recovery codes."
  end

  # POST /users/request-email-otp
  def request_email_otp
    user = pending_otp_user
    unless user
      redirect_to new_user_session_path, alert: "Session expired. Please sign in again."
      return
    end

    if user.internal_staff?
      redirect_to users_otp_challenge_path, alert: "Your account requires an authenticator app."
      return
    end

    if user.email_otp_recently_sent?
      redirect_to users_otp_challenge_path, notice: "A code was already sent. Please wait before requesting another."
      return
    end

    code = user.generate_email_otp!
    OtpMailer.email_otp(user: user, code: code).deliver_later
    UserAuditEvents::Record.call(user: user, event_type: :email_otp_sent, request: request)
    session[:otp_via_email] = true
    redirect_to users_otp_challenge_path, notice: "A sign-in code has been sent to #{user.email}."
  end

  def destroy
    UserAuditEvents::Record.call(user: current_user, event_type: :signed_out, request: request)
    super
  end

  private

  def handle_two_factor_challenge
    user = User.find_by(email: sign_in_params[:email]&.strip&.downcase)
    return unless user&.valid_password?(sign_in_params[:password].to_s)

    if user.otp_required_for_login
      session[:otp_user_id] = user.id.to_s
      redirect_to users_otp_challenge_path
    elsif user.internal_staff?
      session[:totp_setup_user_id] = user.id.to_s
      redirect_to users_totp_enrollment_path
    else
      session[:otp_user_id]   = user.id.to_s
      session[:otp_via_email] = true
      code = user.generate_email_otp!
      OtpMailer.email_otp(user: user, code: code).deliver_later
      UserAuditEvents::Record.call(user: user, event_type: :email_otp_sent, request: request)
      redirect_to users_otp_challenge_path
    end
  end

  def pending_otp_user
    return unless session[:otp_user_id]
    User.find_by(id: session[:otp_user_id])
  end

  def pending_totp_setup_user
    return unless session[:totp_setup_user_id]
    User.find_by(id: session[:totp_setup_user_id])
  end

  def submitted_otp
    params.dig(:user, :otp_attempt).to_s.gsub(/\s+/, "")
  end
end
