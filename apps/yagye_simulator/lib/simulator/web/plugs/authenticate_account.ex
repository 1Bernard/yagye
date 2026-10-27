defmodule Simulator.Web.Plugs.AuthenticateAccount do
  @moduledoc false

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  def init(opts), do: opts

  def call(conn, _opts) do
    key = extract_key(conn)
    authenticate(conn, key)
  end

  # Header takes precedence; query param is a fallback for browser download links
  # in the local admin UI (dev/test only — never expose this in production).
  defp extract_key(conn) do
    case get_req_header(conn, "x-api-key") do
      [key] ->
        key

      _ ->
        conn
        |> Plug.Conn.fetch_query_params()
        |> Map.get(:query_params)
        |> Map.get("api_key")
    end
  end

  defp authenticate(conn, nil) do
    conn
    |> put_status(401)
    |> json(%{error: "missing_api_key", message: "x-api-key header is required."})
    |> halt()
  end

  defp authenticate(conn, key) do
    case Simulator.Accounts.authenticate(key) do
      {:ok, account} ->
        assign(conn, :current_account, account)

      {:error, :invalid_key} ->
        conn
        |> put_status(401)
        |> json(%{error: "invalid_api_key", message: "The provided API key is not valid."})
        |> halt()
    end
  end
end
