# frozen_string_literal: true

module Developers
  class ProvidersController < ApplicationController
    before_action :require_approved_merchant!

    SUPPORTED_PSPS = [
      { code: "paystack",    label: "Paystack",    color: "#00C3F7" },
      { code: "flutterwave", label: "Flutterwave", color: "#F5A623" }
    ].freeze

    def index
      authorize :developers, :manage_psp_connections?
      result = core.list_provider_connections(current_user.merchant_code)
      @connections = result.success? ? (result.body["data"] || []) : []
      render Developers::ProvidersIndexView.new(connections: @connections, psps: SUPPORTED_PSPS)
    end

    def new
      authorize :developers, :manage_psp_connections?
      render Developers::ProviderFormView.new(connection: nil, psps: SUPPORTED_PSPS, mode: :new,
                                              error: nil)
    end

    def create
      authorize :developers, :manage_psp_connections?
      attrs = {
        provider_code:   params[:provider_code],
        mode:            params[:mode].presence || "sandbox",
        priority:        params[:priority].to_i.clamp(1, 99),
        enabled_methods: Array(params[:enabled_methods]).reject(&:empty?),
        api_key:         params[:api_key],
        secret_key:      params[:secret_key],
        base_url:        params[:base_url].presence
      }.compact

      result = core.create_provider_connection(current_user.merchant_code, attrs)

      if result.success?
        audit(action: "provider_connection.created", resource_type: "merchant_provider_connection",
              outcome: "succeeded", metadata: { provider_code: attrs[:provider_code], mode: attrs[:mode] })
        redirect_to developers_providers_path, notice: "#{psp_label(attrs[:provider_code])} connected successfully."
      else
        audit(action: "provider_connection.created", resource_type: "merchant_provider_connection",
              outcome: "failed", metadata: { provider_code: attrs[:provider_code] })
        render Developers::ProviderFormView.new(connection: nil, psps: SUPPORTED_PSPS, mode: :new,
                                                error: result.error_message)
      end
    end

    def edit
      authorize :developers, :manage_psp_connections?
      result = core.list_provider_connections(current_user.merchant_code)
      connections = result.success? ? (result.body["data"] || []) : []
      connection = connections.find { |c| c["id"] == params[:id] }
      render Developers::ProviderFormView.new(connection: connection, psps: SUPPORTED_PSPS, mode: :edit,
                                              error: nil)
    end

    def update
      authorize :developers, :manage_psp_connections?
      attrs = {
        priority:        params[:priority].to_i.clamp(1, 99),
        status:          params[:status].presence,
        enabled_methods: Array(params[:enabled_methods]).reject(&:empty?)
      }.compact

      result = core.update_provider_connection(params[:id], attrs)

      if result.success?
        redirect_to developers_providers_path, notice: "Provider updated."
      else
        redirect_to developers_providers_path, alert: result.error_message
      end
    end

    def deactivate
      authorize :developers, :manage_psp_connections?
      result = core.deactivate_provider_connection(params[:id])

      if result.success?
        audit(action: "provider_connection.deactivated", resource_type: "merchant_provider_connection",
              outcome: "succeeded", resource_code: params[:id])
        redirect_to developers_providers_path, notice: "Provider disabled."
      else
        redirect_to developers_providers_path, alert: result.error_message
      end
    end

    private

    def require_approved_merchant!
      return if current_user.internal_staff?
      unless (current_user.merchant_tier || 0) >= 2
        redirect_to developers_path,
          alert: "PSP management requires a submitted KYB application."
      end
    end

    def psp_label(code)
      SUPPORTED_PSPS.find { |p| p[:code] == code }&.dig(:label) || code.to_s.titleize
    end

    def core = CoreApiClient.new
  end
end
