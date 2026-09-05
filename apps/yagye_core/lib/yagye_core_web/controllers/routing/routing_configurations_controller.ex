defmodule YagyeCoreWeb.Controllers.Routing.RoutingConfigurationsController do
  @moduledoc false

  use YagyeCoreWeb, :controller

  alias YagyeCore.Routing
  alias YagyeCoreWeb.Response

  action_fallback YagyeCoreWeb.FallbackController

  def index(conn, params) do
    opts = [scope: params["scope"] || "platform", state: params["state"]]

    with {:ok, configs} <- Routing.list_configurations(opts) do
      Response.ok(conn, %{object: "list", data: Enum.map(configs, &config_json/1)})
    end
  end

  def create(conn, params) do
    attrs = %{
      scope: params["scope"] || "platform",
      merchant_id: params["merchant_id"],
      name: params["name"],
      description: params["description"],
      graph_payload: params["graph_payload"]
    }

    with {:ok, config} <- Routing.create_configuration(attrs) do
      conn |> put_status(201) |> json(config_json(config))
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, config} <- Routing.get_configuration(id) do
      Response.ok(conn, config_json(config))
    end
  end

  def update(conn, %{"id" => id} = params) do
    attrs = %{
      name: params["name"],
      description: params["description"],
      graph_payload: params["graph_payload"]
    }

    with {:ok, config} <- Routing.get_configuration(id),
         {:ok, updated} <- Routing.update_configuration(config, attrs) do
      Response.ok(conn, config_json(updated))
    end
  end

  def publish(conn, %{"id" => id}) do
    with {:ok, config} <- Routing.get_configuration(id),
         {:ok, published} <- Routing.publish_configuration(config) do
      Response.ok(conn, config_json(published))
    end
  end

  defp config_json(c) do
    %{
      id: c.id,
      public_id: c.public_id,
      object: "routing_configuration",
      scope: c.scope,
      merchant_id: c.merchant_id,
      name: c.name,
      description: c.description,
      schema_version: c.schema_version,
      graph_payload: c.graph_payload,
      compiled_rules: c.compiled_rules,
      state: c.state,
      published_at: c.published_at,
      archived_at: c.archived_at,
      inserted_at: c.inserted_at,
      updated_at: c.updated_at
    }
  end
end
