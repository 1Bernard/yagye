defmodule YagyeCoreWeb.Plugs.Idempotency do
  @moduledoc false

  # Idempotency enforcement for mutating HTTP methods.
  #
  # When the client sends an Idempotency-Key header:
  #   - First request  → claims the key, stores idem_key in assigns, continues
  #   - Repeat request → replays the stored response verbatim (200/201/422/etc.)
  #   - Concurrent dupe → 409 while the first request's lease is held (30s)
  #   - Body mismatch  → 422 (key reused with different payload)
  #   - Prior failure  → 422 (client must use a new key to retry)
  #
  # The Idempotency-Key header is optional. Requests without it proceed normally
  # with no idempotency guarantee. Controllers call Idempotency.complete/5 on
  # success, reading conn.assigns.idempotency_key for the key ID.
  #
  # Must run after Authenticate (requires conn.assigns.merchant_id).

  @behaviour Plug

  import Plug.Conn

  alias YagyeCore.Idempotency

  @mutating_methods ~w[POST PUT PATCH DELETE]

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%{method: method} = conn, _opts) when method not in @mutating_methods, do: conn

  def call(conn, _opts) do
    case get_req_header(conn, "idempotency-key") do
      [] -> conn
      [key | _] -> process(conn, key)
    end
  end

  defp process(conn, key) do
    merchant_id = conn.assigns.merchant_id
    fingerprint = fingerprint(conn)

    case Idempotency.claim(merchant_id, key, fingerprint) do
      {:ok, :claimed, idem_key} ->
        assign(conn, :idempotency_key, idem_key)

      {:ok, :replay, idem_key} ->
        conn
        |> put_resp_content_type("application/json")
        |> put_resp_header("idempotency-replayed", "true")
        |> send_resp(idem_key.response_status, Jason.encode!(idem_key.response_body))
        |> halt()

      {:error, :in_progress} ->
        halt_error(
          conn,
          409,
          "idempotency_in_progress",
          "A request with this idempotency key is already in progress"
        )

      {:error, :fingerprint_mismatch} ->
        halt_error(
          conn,
          422,
          "idempotency_key_reuse",
          "Idempotency key reused with a different request body"
        )

      {:error, :previous_attempt_failed} ->
        halt_error(
          conn,
          422,
          "previous_attempt_failed",
          "Previous attempt failed — use a new idempotency key to retry"
        )

      {:error, :lease_expired} ->
        halt_error(
          conn,
          409,
          "idempotency_lease_expired",
          "Previous request lease expired — safe to retry with the same key"
        )
    end
  end

  defp fingerprint(conn) do
    body = conn.assigns[:raw_body] || ""
    :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)
  end

  defp halt_error(conn, status, code, message) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(%{error: %{code: code, message: message}}))
    |> halt()
  end
end
