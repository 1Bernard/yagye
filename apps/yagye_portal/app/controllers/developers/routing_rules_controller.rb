# frozen_string_literal: true

module Developers
  class RoutingRulesController < ApplicationController
    # Native rails — Yagye holds platform-level live credentials for these.
    # These are the only providers valid in a published (live) routing configuration.
    NATIVE_PROVIDERS = [
      { code: "mtn_momo",     label: "MTN MoMo",        color: "#FFCC00", kind: "native_rail" },
      { code: "telecel_cash", label: "Telecel Cash",     color: "#E2001A", kind: "native_rail" },
      { code: "airteltigo",   label: "AirtelTigo Money", color: "#FF6B00", kind: "native_rail" }
    ].freeze

    # Simulator — test/development only. Has no live-mode credentials.
    # Shown in the graph editor so ops can build and preview configurations,
    # but publishing a config that routes to the Simulator will fail at Core.
    SIMULATOR_PROVIDERS = [
      { code: "simulator", label: "Gateway Simulator", color: "#6b7280", kind: "simulator" }
    ].freeze

    PROVIDERS = (NATIVE_PROVIDERS + SIMULATOR_PROVIDERS).freeze

    def index
      authorize :developers, :manage_routing_rules?
      result = core.list_routing_configurations(scope: "platform")
      @configurations = result.success? ? result.body["data"] : []
      render Developers::RoutingRulesIndexView.new(configurations: @configurations)
    end

    def new
      authorize :developers, :manage_routing_rules?
      render Developers::RoutingGraphView.new(
        configuration: nil,
        providers: PROVIDERS,
        mode: :new
      )
    end

    def edit
      authorize :developers, :manage_routing_rules?
      result = core.get_routing_configuration(params[:id])
      return redirect_to developers_routing_rules_path, alert: result.error_message unless result.success?

      render Developers::RoutingGraphView.new(
        configuration: result.body,
        providers: PROVIDERS,
        mode: :edit
      )
    end

    def create
      authorize :developers, :manage_routing_rules?
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
      authorize :developers, :manage_routing_rules?
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
      authorize :developers, :manage_routing_rules?
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
  end
end
