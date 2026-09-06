# frozen_string_literal: true

module Account
  class PasskeysController < ApplicationController
    # POST /settings/passkeys/register-challenge
    def register_challenge
      authorize :settings, :update?

      options = WebAuthn::Credential.options_for_create(
        user: { id: current_user.id.to_s, name: current_user.email, display_name: current_user.full_name },
        exclude: current_user.passkey_credentials.pluck(:external_id)
      )
      session[:passkey_register_challenge] = options.challenge
      render json: options
    end

    # POST /settings/passkeys
    def create
      authorize :settings, :update?

      challenge = session.delete(:passkey_register_challenge)
      return render json: { error: "expired" }, status: :unprocessable_entity unless challenge

      credential = WebAuthn::Credential.from_create(parsed_credential)
      credential.verify(challenge)

      current_user.passkey_credentials.create!(
        external_id: credential.id,
        public_key:  credential.public_key,
        sign_count:  credential.sign_count,
        nickname:    params[:nickname].presence || default_nickname
      )

      render json: { ok: true }
    rescue WebAuthn::Error => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    # DELETE /settings/passkeys/:id
    def destroy
      authorize :settings, :update?

      cred = current_user.passkey_credentials.find(params[:id])
      cred.destroy!
      redirect_to settings_path(tab: "security"), notice: "Passkey removed."
    end

    private

    def parsed_credential
      raw = params[:credential]
      if raw.present?
        raw.is_a?(String) ? JSON.parse(raw) : raw.to_unsafe_h
      else
        # JS sent the credential object as the JSON root (no wrapper key)
        params.except(:controller, :action, :authenticity_token, :nickname).to_unsafe_h
      end
    end

    def default_nickname
      "Passkey · #{Time.current.strftime('%b %d, %Y')}"
    end
  end
end
