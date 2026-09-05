# frozen_string_literal: true

module Account
  class TotpController < ApplicationController
    # GET /settings/totp/new
    def new
      authorize :settings, :update?
      return redirect_to settings_path(tab: "security"), notice: "Two-factor authentication is already enabled." if current_user.otp_required_for_login

      secret = User.generate_otp_secret
      session[:pending_otp_secret] = secret

      totp = ROTP::TOTP.new(secret, issuer: "Yagye")
      uri  = totp.provisioning_uri(current_user.email)
      qr   = RQRCode::QRCode.new(uri)
      svg  = qr.as_svg(
        module_size: 4,
        shape_rendering: "crispEdges",
        module_color: "#1f2937",
        background_color: "#ffffff",
        standalone: true,
        use_path: true
      )

      render Settings::TotpSetupView.new(
        current_user: current_user,
        otp_secret:   secret,
        qr_svg:       svg.html_safe
      )
    end

    # POST /settings/totp
    def create
      authorize :settings, :update?

      secret = session[:pending_otp_secret]
      unless secret.present?
        return redirect_to settings_totp_new_path, alert: "Setup session expired. Please start again."
      end

      totp = ROTP::TOTP.new(secret, issuer: "Yagye")
      unless totp.verify(params[:otp_code].to_s.gsub(/\s+/, ""), drift_behind: 15, drift_ahead: 15)
        return redirect_to settings_totp_new_path, alert: "Invalid code. Please try again — make sure your device clock is correct."
      end

      current_user.update!(otp_secret: secret, otp_required_for_login: true)
      session.delete(:pending_otp_secret)

      plain_codes = current_user.generate_recovery_codes!
      session[:totp_recovery_codes] = plain_codes

      UserAuditEvents::Record.call(user: current_user, event_type: :totp_enabled, request: request)

      redirect_to settings_totp_recovery_codes_path
    end

    # GET /settings/totp/recovery-codes
    def recovery_codes
      authorize :settings, :update?

      codes = session.delete(:totp_recovery_codes)
      unless codes.present?
        return redirect_to settings_path(tab: "security")
      end

      render Settings::TotpRecoveryCodesView.new(
        current_user: current_user,
        recovery_codes: codes
      )
    end

    # DELETE /settings/totp
    def destroy
      authorize :settings, :update?

      unless current_user.valid_password?(params[:current_password].to_s)
        return redirect_to settings_path(tab: "security"), alert: "Incorrect password. Two-factor authentication was not disabled."
      end

      current_user.update!(
        otp_required_for_login: false,
        otp_secret: nil,
        otp_recovery_codes: nil
      )
      UserAuditEvents::Record.call(user: current_user, event_type: :totp_disabled, request: request)

      redirect_to settings_path(tab: "security"), notice: "Two-factor authentication has been disabled."
    end
  end
end
