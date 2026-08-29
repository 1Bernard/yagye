# frozen_string_literal: true

class Users::PasswordsController < Devise::PasswordsController
  skip_after_action :verify_authorized

  def new
    self.resource = resource_class.new
    render Auth::ForgotPasswordView.new(resource: resource, csrf_token: form_authenticity_token)
  end

  def edit
    self.resource = resource_class.new
    render Auth::ResetPasswordView.new(
      resource: resource,
      csrf_token: form_authenticity_token,
      token: params[:reset_password_token]
    )
  end
end
