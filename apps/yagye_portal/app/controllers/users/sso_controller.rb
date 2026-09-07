# frozen_string_literal: true

class Users::SsoController < ApplicationController
  skip_before_action :authenticate_user!
  skip_after_action  :verify_authorized
  skip_before_action :verify_authenticity_token, only: :callback

  # GET /auth/sso/check?email=...
  # JSON — returns {active: bool, name: string|nil}
  def check
    config = SsoConfiguration.find_for_email(params[:email].to_s)
    render json: { active: config.present?, name: config&.name }
  end

  # GET /auth/sso/initiate?domain=acme.com
  def initiate
    config = SsoConfiguration.find_for_domain(params[:domain].to_s)

    unless config
      redirect_to new_user_session_path, alert: "SSO is not configured for that domain."
      return
    end

    session[:sso_domain] = config.email_domain
    auth_request         = OneLogin::RubySaml::Authrequest.new
    redirect_to auth_request.create(saml_settings(config)), allow_other_host: true
  end

  # POST /auth/saml/callback
  def callback
    domain = session.delete(:sso_domain)
    config = domain && SsoConfiguration.find_for_domain(domain)

    unless config
      redirect_to new_user_session_path, alert: "SSO session expired. Please try again."
      return
    end

    response = OneLogin::RubySaml::Response.new(
      params[:SAMLResponse],
      settings: saml_settings(config)
    )

    unless response.is_valid?
      Rails.logger.warn("SSO callback invalid: #{response.errors.join(', ')}")
      redirect_to new_user_session_path, alert: "SSO sign-in failed. Please contact your administrator."
      return
    end

    email = response.name_id.to_s.strip.downcase
    user  = User.find_by(email: email)

    unless user
      redirect_to new_user_session_path,
                  alert: "No account found for #{email}. Ask your administrator to invite you first."
      return
    end

    sign_in(:user, user)
    UserAuditEvents::Record.call(user: user, event_type: :signed_in, request: request)
    redirect_to after_sign_in_path_for(user)
  end

  private

  def saml_settings(config)
    settings = OneLogin::RubySaml::Settings.new
    settings.idp_sso_target_url             = config.idp_sso_target_url
    settings.idp_entity_id                  = config.idp_entity_id.presence
    settings.idp_cert                       = config.idp_cert
    settings.sp_entity_id                   = "#{sp_base_url}/auth/saml/metadata"
    settings.assertion_consumer_service_url = "#{sp_base_url}/auth/saml/callback"
    settings.name_identifier_format         = "urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress"
    settings
  end

  def sp_base_url
    ENV.fetch("SP_BASE_URL", request.base_url)
  end
end
