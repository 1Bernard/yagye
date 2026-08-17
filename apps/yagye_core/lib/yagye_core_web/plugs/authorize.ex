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
  def init(opts), do: Keyword.fetch!(opts, :scope)

  @impl Plug
  def call(conn, required_scope) do
    scopes = conn.assigns[:api_key].scopes || []

    if required_scope in scopes or "*" in scopes do
      conn
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(
        403,
        Jason.encode!(%{
          error: %{code: "forbidden", message: "API key does not have the required scope: #{required_scope}"}
        })
      )
      |> halt()
    end
  end
end
