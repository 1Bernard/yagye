# frozen_string_literal: true

# Ops-only CRUD for SSO configurations.
# Enterprise merchants cannot edit — they view their config via the settings tab.
class SsoConfigurationsController < ApplicationController
  before_action :set_config,   only: %i[edit update destroy]
  before_action :authorize_ops

  def new
    @config = SsoConfiguration.new
    render Settings::SsoFormView.new(config: @config, action: :new)
  end

  def create
    @config = SsoConfiguration.new(config_params)
    if @config.save
      redirect_to settings_path(tab: "sso"), notice: "SSO configuration created."
    else
      render Settings::SsoFormView.new(config: @config, action: :new), status: :unprocessable_entity
    end
  end

  def edit
    render Settings::SsoFormView.new(config: @config, action: :edit)
  end

  def update
    if @config.update(config_params)
      redirect_to settings_path(tab: "sso"), notice: "SSO configuration updated."
    else
      render Settings::SsoFormView.new(config: @config, action: :edit), status: :unprocessable_entity
    end
  end

  def destroy
    @config.destroy
    redirect_to settings_path(tab: "sso"), notice: "SSO configuration removed."
  end

  private

  def set_config
    @config = SsoConfiguration.find(params[:id])
  end

  def authorize_ops
    authorize :sso_configuration, :manage?
  end

  def config_params
    params.require(:sso_configuration).permit(
      :name, :email_domain, :merchant_code,
      :idp_sso_target_url, :idp_entity_id, :idp_cert, :active
    )
  end
end
