defmodule YagyeCoreWeb.Plugs.Authenticate do
  @moduledoc false

  @behaviour Plug

  import Plug.Conn

  alias YagyeCore.Merchants

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    case extract_key(conn) do
      {:ok, raw_key} ->
        case Merchants.authenticate(raw_key) do
          {:ok, api_key} ->
            conn
            |> assign(:api_key, api_key)
            |> assign(:merchant_id, api_key.merchant_id)
            |> assign(:mode, api_key.mode)

          {:error, :invalid_credentials} ->
            halt_unauthorized(conn)
        end

      {:error, :missing} ->
        halt_unauthorized(conn)
    end
  end

  # Accepts Authorization: Bearer <key> or X-API-Key: <key>
  defp extract_key(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> key | _] ->
        {:ok, String.trim(key)}

      _ ->
        case get_req_header(conn, "x-api-key") do
          [key | _] -> {:ok, key}
          _ -> {:error, :missing}
        end
    end
  end

  defp halt_unauthorized(conn) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(
      401,
      Jason.encode!(%{error: %{code: "unauthorized", message: "Invalid or missing API key"}})
    )
    |> halt()
  end
end
