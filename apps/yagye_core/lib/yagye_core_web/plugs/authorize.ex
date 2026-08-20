defmodule YagyeCoreWeb.Plugs.Authorize do
  @moduledoc false

  # Scope-based authorization. Used as a controller-level plug so each action
  # can declare its own required scope:
  #
  #   plug YagyeCoreWeb.Plugs.Authorize, scope: "merchants:write" when action in [:create]
  #   plug YagyeCoreWeb.Plugs.Authorize, scope: "merchants:read"  when action in [:show]
  #
  # The wildcard scope "*" grants all access (for admin/internal keys).
  # Must run after Authenticate.

  @behaviour Plug

  import Plug.Conn

  @impl Plug
  def init(opts) do
    {Keyword.fetch!(opts, :scope), Keyword.get(opts, :kind)}
  end

  @impl Plug
  def call(conn, {required_scope, required_kind}) do
    api_key = conn.assigns[:api_key]
    scopes = api_key.scopes || []

    cond do
      required_scope not in scopes and "*" not in scopes ->
        forbidden(conn, "API key does not have the required scope: #{required_scope}")

      required_kind == :secret and api_key.kind != "secret" ->
        forbidden(conn, "This operation requires a secret API key")

      true ->
        conn
    end
  end

  defp forbidden(conn, message) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(403, Jason.encode!(%{error: %{code: "forbidden", message: message}}))
    |> halt()
  end
end
