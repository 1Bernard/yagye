class Users::SessionsController < Devise::SessionsController
  # Intercept the normal sign-in POST.
  # If the user has TOTP enrolled, redirect to the OTP challenge instead of
  # completing the session — Devise's own `create` action never runs in that case.
  # For wrong passwords or users without TOTP, we fall through to Devise's `create`
  # which handles errors and normal sign-in exactly as before.
  prepend_before_action :handle_two_factor_challenge, only: :create

  skip_before_action :authenticate_user!, only: %i[new otp_challenge verify_otp]
  skip_after_action  :verify_authorized,  only: %i[new otp_challenge verify_otp]

  def new
    self.resource = resource_class.new
    render Auth::SignInPage.new(resource: resource, csrf_token: form_authenticity_token)
  end

  # GET /users/otp-challenge
  def otp_challenge
    resource = pending_otp_user
    redirect_to(new_user_session_path) and return unless resource
    render Auth::OtpPage.new(csrf_token: form_authenticity_token)
  end

  # POST /users/otp-challenge
  def verify_otp
    user = pending_otp_user

    unless user
      redirect_to new_user_session_path, alert: "Session expired. Please sign in again."
      return
    end

    if user.validate_and_consume_otp!(submitted_otp)
      session.delete(:otp_user_id)
      sign_in(:user, user)
      redirect_to after_sign_in_path_for(user)
    else
      flash.now[:alert] = "Invalid authentication code. Check your authenticator app and try again."
      @resource = user
      render :otp_challenge, status: :unprocessable_entity
    end
  end

  private

  def handle_two_factor_challenge
    user = User.find_by(email: sign_in_params[:email]&.strip&.downcase)
    return unless user&.valid_password?(sign_in_params[:password].to_s)
    return unless user.otp_required_for_login

    session[:otp_user_id] = user.id.to_s
    redirect_to users_otp_challenge_path
  end

  def pending_otp_user
    return unless session[:otp_user_id]

    User.find_by(id: session[:otp_user_id])
  end

  def submitted_otp
    params.dig(:user, :otp_attempt).to_s.gsub(/\s+/, "")
  end
end
