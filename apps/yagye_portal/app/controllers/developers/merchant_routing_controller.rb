# frozen_string_literal: true

module Developers
  class MerchantRoutingController < ApplicationController
    before_action :require_approved_merchant!

    def index
      authorize :developers, :manage_merchant_routing?
      result = core.list_routing_configurations(
        scope: "merchant",
        merchant_code: current_user.merchant_code
      )
      @configurations = result.success? ? (result.body["data"] || []) : []
      render Developers::MerchantRoutingIndexView.new(configurations: @configurations)
    end

    def new
      authorize :developers, :manage_merchant_routing?
      conn_result = core.list_provider_connections(current_user.merchant_code)
      providers = build_provider_list(conn_result)
      render Developers::MerchantRoutingGraphView.new(
        configuration: nil,
        providers: providers,
        mode: :new
      )
    end

    def edit
      authorize :developers, :manage_merchant_routing?
      config_result = core.get_routing_configuration(params[:id])
      conn_result   = core.list_provider_connections(current_user.merchant_code)

      unless config_result.success?
        return redirect_to developers_merchant_routing_index_path, alert: "Configuration not found."
      end

      providers = build_provider_list(conn_result)
      render Developers::MerchantRoutingGraphView.new(
        configuration: config_result.body,
        providers: providers,
        mode: :edit
      )
    end

    def create
      authorize :developers, :manage_merchant_routing?
      conn_result = core.list_provider_connections(current_user.merchant_code)
      merchant_id = conn_result.success? ? conn_result.body["merchant_id"] : nil
      payload     = JSON.parse(params[:graph_payload] || "{}")

      result = core.create_routing_configuration(
        name:          params[:name].presence || "My routing",
        scope:         "merchant",
        merchant_id:   merchant_id,
        description:   params[:description],
        graph_payload: payload
      )

      if result.success?
        audit(action: "merchant_routing.created", resource_type: "routing_configuration",
              outcome: "succeeded", resource_code: result.body["id"],
              metadata: { name: params[:name] })
        redirect_to edit_developers_merchant_routing_path(result.body["id"]),
                    notice: "Configuration saved as draft."
      else
        audit(action: "merchant_routing.created", resource_type: "routing_configuration",
              outcome: "failed", metadata: { name: params[:name] })
        redirect_to new_developers_merchant_routing_path, alert: result.error_message
      end
    rescue JSON::ParserError
      redirect_to new_developers_merchant_routing_path, alert: "Invalid graph payload — please try again."
    end

    def update
      authorize :developers, :manage_merchant_routing?
      payload = JSON.parse(params[:graph_payload] || "{}")
      result  = core.update_routing_configuration(
        params[:id],
        name:          params[:name].presence || "My routing",
        description:   params[:description],
        graph_payload: payload
      )

      if result.success?
        audit(action: "merchant_routing.updated", resource_type: "routing_configuration",
              outcome: "succeeded", resource_code: params[:id])
        redirect_to edit_developers_merchant_routing_path(params[:id]),
                    notice: "Configuration updated."
      else
        redirect_to edit_developers_merchant_routing_path(params[:id]),
                    alert: result.error_message
      end
    rescue JSON::ParserError
      redirect_to edit_developers_merchant_routing_path(params[:id]),
                  alert: "Invalid graph payload — please try again."
    end

    def publish
      authorize :developers, :manage_merchant_routing?
      result = core.activate_routing_configuration(params[:id])

      if result.success?
        audit(action: "merchant_routing.published", resource_type: "routing_configuration",
              outcome: "succeeded", resource_code: params[:id])
        redirect_to developers_merchant_routing_index_path,
                    notice: "Configuration published and active."
      else
        audit(action: "merchant_routing.published", resource_type: "routing_configuration",
              outcome: "failed", resource_code: params[:id])
        redirect_to edit_developers_merchant_routing_path(params[:id]),
                    alert: result.error_message
      end
    end

    private

    def build_provider_list(conn_result)
      return [] unless conn_result.success?

      (conn_result.body["data"] || [])
        .select { |c| c["status"] == "active" }
        .map do |c|
          {
            code:  c["provider_code"],
            label: c["provider_name"] || c["provider_code"].to_s.titleize,
            color: psp_color(c["provider_code"]),
            kind:  "external_psp"
          }
        end
    end

    def psp_color(code)
      {
        "paystack"     => "#00C3F7",
        "paystack_gh"  => "#00C3F7",
        "flutterwave"  => "#F5A623",
        "flutterwave_gh" => "#F5A623"
      }.fetch(code.to_s, "#6b7280")
    end

    def require_approved_merchant!
      return if current_user.internal_staff?
      unless (current_user.merchant_tier || 0) >= 2
        redirect_to developers_path,
          alert: "Routing customization requires a submitted KYB application."
      end
    end

    def core = CoreApiClient.new
  end
end
