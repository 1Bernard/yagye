# frozen_string_literal: true

class Users::PasskeySessionsController < ApplicationController
  skip_before_action :authenticate_user!
  skip_before_action :set_current_user
  skip_before_action :set_portal_mode
  skip_after_action  :verify_authorized

  # POST /users/passkey-challenge — returns WebAuthn options JSON
  def challenge
    options = WebAuthn::Credential.options_for_get
    session[:passkey_auth_challenge] = options.challenge
    render json: options
  end

  # POST /users/passkey-auth — verifies assertion, signs user in
  def authenticate
    challenge = session.delete(:passkey_auth_challenge)
    return redirect_to new_user_session_path, alert: "Session expired. Please try again." unless challenge

    credential_json = params[:credential].is_a?(String) ? JSON.parse(params[:credential]) : params[:credential].to_unsafe_h
    assertion = WebAuthn::Credential.from_get(credential_json)

    passkey = PasskeyCredential.find_by(external_id: assertion.id)
    return redirect_to new_user_session_path, alert: "Passkey not recognised." unless passkey

    assertion.verify(challenge, public_key: passkey.public_key, sign_count: passkey.sign_count)
    passkey.update!(sign_count: assertion.sign_count, last_used_at: Time.current)

    user = passkey.user
    sign_in(:user, user)
    redirect_to after_sign_in_path_for(user), status: :see_other
  rescue WebAuthn::Error => e
    Rails.logger.error "[PasskeyAuth] #{e.class}: #{e.message}"
    redirect_to new_user_session_path, alert: "Passkey verification failed. Please try again."
  end
end
