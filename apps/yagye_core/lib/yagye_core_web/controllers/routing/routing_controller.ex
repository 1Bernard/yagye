defmodule YagyeCoreWeb.Controllers.Routing.RoutingController do
  @moduledoc false

  # Internal-only: reachable via /internal pipeline (X-Service-Token auth).
  # Used by Yagye ops portal to manage platform-scope routing rules and,
  # at P16, by enterprise merchants to manage their own overrides.

  use YagyeCoreWeb, :controller

  alias YagyeCore.Routing
  alias YagyeCoreWeb.Response

  action_fallback YagyeCoreWeb.FallbackController

  def index(conn, params) do
    opts = [
      mode: params["mode"] || "live",
      merchant_id: params["merchant_id"]
    ]

    with {:ok, rules} <- Routing.list_rules(opts) do
      Response.ok(conn, %{object: "list", data: Enum.map(rules, &rule_json/1)})
    end
  end

  def create(conn, params) do
    attrs = %{
      scope: params["scope"],
      merchant_id: params["merchant_id"],
      mode: params["mode"],
      name: params["name"],
      priority: params["priority"],
      active: Map.get(params, "active", true)
    }

    with {:ok, rule} <- Routing.create_rule(attrs) do
      conn |> put_status(201) |> json(rule_json(rule))
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, rule} <- Routing.get_rule(id) do
      Response.ok(conn, rule_json(rule))
    end
  end

  def deactivate(conn, %{"id" => id}) do
    with {:ok, rule} <- Routing.get_rule(id),
         {:ok, updated} <- Routing.deactivate_rule(rule) do
      Response.ok(conn, rule_json(updated))
    end
  end

  defp rule_json(rule) do
    %{
      id: rule.id,
      object: "routing_rule",
      scope: rule.scope,
      merchant_id: rule.merchant_id,
      mode: rule.mode,
      name: rule.name,
      priority: rule.priority,
      active: rule.active,
      inserted_at: rule.inserted_at,
      updated_at: rule.updated_at
    }
  end
end
