defmodule YagyeCoreWeb.Plugs.AuditLog do
  @moduledoc false

  # Registers a before_send hook that writes one row to api_requests after every
  # request completes, including unauthenticated failures (merchant_id is nullable).
  #
  # Place this FIRST in the API pipeline so it wraps all downstream plugs.
  # The before_send callback fires after the controller has finished and all
  # assigns are populated.

  @behaviour Plug

  import Plug.Conn

  alias YagyeCore.Shared.ApiRequest

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    start = System.monotonic_time(:millisecond)

    register_before_send(conn, fn conn ->
      duration_ms = System.monotonic_time(:millisecond) - start

      ApiRequest.log(%{
        merchant_id: conn.assigns[:merchant_id],
        api_key_id: get_in(conn.assigns, [:api_key, Access.key(:id)]),
        mode: conn.assigns[:mode],
        method: conn.method,
        path: conn.request_path,
        api_version: get_req_header(conn, "x-api-version") |> List.first("2026-01-01"),
        status: conn.status,
        duration_ms: duration_ms,
        correlation_id: conn.assigns[:correlation_id],
        idempotency_key: get_req_header(conn, "idempotency-key") |> List.first(),
        request_body_sha256: body_hash(conn.assigns[:raw_body]),
        error_code: conn.assigns[:error_code]
      })

      conn
    end)
  end

  defp body_hash(nil), do: nil
  defp body_hash(""), do: nil

  defp body_hash(body) do
    :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)
  end
end
