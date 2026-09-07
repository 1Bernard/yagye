defmodule YagyeCoreWeb.Controllers.Internal.ApiKeysController do
  @moduledoc """
  Internal endpoint for portal → Core API key provisioning.
  Uses service-token auth (X-Service-Token) — not merchant API key auth —
  so the portal can generate the first key for a merchant before they have any.
  """

  use YagyeCoreWeb, :controller

  alias YagyeCore.Merchants
  alias YagyeCoreWeb.Controllers.ApiKeys.ApiKeyJSON

  action_fallback YagyeCoreWeb.FallbackController

  def create(conn, %{"code" => merchant_code} = params) do
    with {:ok, merchant} <- Merchants.get_merchant(merchant_code),
         attrs = build_attrs(params, conn),
         {:ok, {api_key, raw_key, _event}} <- Merchants.issue_api_key(merchant.id, attrs) do
      conn
      |> put_status(201)
      |> json(ApiKeyJSON.data(api_key, raw_key))
    else
      {:error, :not_found} ->
        conn
        |> put_status(404)
        |> json(%{error: %{code: "not_found", message: "Merchant not found"}})

      {:error, reason} ->
        conn
        |> put_status(422)
        |> json(%{error: %{code: "unprocessable", message: inspect(reason)}})
    end
  end

  defp build_attrs(params, _conn) do
    %{
      mode: params["mode"] || "live",
      kind: params["kind"] || "secret",
      label: params["label"] || "",
      scopes: params["scopes"] || [],
      expires_at: params["expires_at"],
      created_by: params["created_by"] || "portal"
    }
  end
end
