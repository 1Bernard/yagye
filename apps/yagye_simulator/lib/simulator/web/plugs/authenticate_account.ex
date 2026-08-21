defmodule Simulator.Web.Plugs.AuthenticateAccount do
  @moduledoc false

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_req_header(conn, "x-api-key") do
      [key] ->
        case Simulator.Accounts.authenticate(key) do
          {:ok, account} ->
            assign(conn, :current_account, account)

          {:error, :invalid_key} ->
            conn
            |> put_status(401)
            |> json(%{error: "invalid_api_key", message: "The provided API key is not valid."})
            |> halt()
        end

      _ ->
        conn
        |> put_status(401)
        |> json(%{error: "missing_api_key", message: "x-api-key header is required."})
        |> halt()
    end
  end
end
