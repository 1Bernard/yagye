# frozen_string_literal: true

module Developers
  class RoutingRulesController < ApplicationController
    before_action :require_internal_staff!

    PROVIDERS = [
      { code: "mtn_momo",     label: "MTN MoMo",    color: "#FFCC00", kind: "native_rail" },
      { code: "telecel_cash", label: "Telecel Cash", color: "#E2001A", kind: "native_rail" },
      { code: "stripe",       label: "Stripe",       color: "#6772E5", kind: "external_psp" },
      { code: "flutterwave",  label: "Flutterwave",  color: "#F5A623", kind: "external_psp" },
      { code: "paystack",     label: "Paystack",     color: "#00C3F7", kind: "external_psp" }
    ].freeze

    def index
      result = core.list_routing_configurations(scope: "platform")
      @configurations = result.success? ? result.body["data"] : []
      render Developers::RoutingRulesIndexView.new(configurations: @configurations)
    end

    def new
      render Developers::RoutingGraphView.new(
        configuration: nil,
        providers: PROVIDERS,
        mode: :new
      )
    end

    def edit
      result = core.get_routing_configuration(params[:id])
      return redirect_to developers_routing_rules_path, alert: result.error_message unless result.success?

      render Developers::RoutingGraphView.new(
        configuration: result.body,
        providers: PROVIDERS,
        mode: :edit
      )
    end

    def create
      payload = JSON.parse(params[:graph_payload] || "{}")
      result = core.create_routing_configuration(
        name: params[:name].presence || "Untitled configuration",
        description: params[:description],
        graph_payload: payload
      )

      if result.success?
        redirect_to edit_developers_routing_rule_path(result.body["id"]),
                    notice: "Configuration saved as draft."
      else
        redirect_to new_developers_routing_rule_path, alert: result.error_message
      end
    end

    def update
      payload = JSON.parse(params[:graph_payload] || "{}")
      result = core.update_routing_configuration(
        params[:id],
        name: params[:name].presence || "Untitled configuration",
        description: params[:description],
        graph_payload: payload
      )

      if result.success?
        redirect_to edit_developers_routing_rule_path(params[:id]),
                    notice: "Configuration updated."
      else
        redirect_to edit_developers_routing_rule_path(params[:id]),
                    alert: result.error_message
      end
    end

    def publish
      result = core.publish_routing_configuration(params[:id])

      if result.success?
        redirect_to developers_routing_rules_path, notice: "Configuration published and active."
      else
        redirect_to edit_developers_routing_rule_path(params[:id]),
                    alert: result.error_message
      end
    end

    private

    def core = CoreApiClient.new

    def require_internal_staff!
      redirect_to root_path, alert: "Not authorised." unless current_user&.internal_staff?
    end
  end
end
