defmodule YagyeCoreWeb.Response do
  @moduledoc false

  # Centralises JSON response shape for all API controllers.
  # Stripe/OpenAI convention: objects returned directly, no data: wrapper.
  # Errors: {"error": {"type": ..., "code": ..., "message": ..., "param": ...}}
  # Trace: X-Request-ID response header (set by Plug.RequestId upstream).

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias Ecto.Changeset

  def ok(conn, object), do: conn |> put_status(200) |> json(object)
  def created(conn, object), do: conn |> put_status(201) |> json(object)

  def not_found(conn) do
    conn
    |> put_status(404)
    |> json(%{error: %{type: "invalid_request_error", code: "not_found", message: "Resource not found"}})
  end

  def forbidden(conn, code, message) do
    conn
    |> put_status(403)
    |> json(%{error: %{type: "invalid_request_error", code: code, message: message}})
  end

  def validation_error(conn, %Changeset{} = changeset) do
    details = Changeset.traverse_errors(changeset, &translate_error/1)
    first_field = details |> Map.keys() |> List.first()

    conn
    |> put_status(422)
    |> json(%{
      error: %{
        type: "invalid_request_error",
        code: "validation_failed",
        message: "One or more fields failed validation",
        param: first_field && to_string(first_field),
        details: details
      }
    })
  end

  def unprocessable(conn, code, message) do
    conn
    |> put_status(422)
    |> json(%{error: %{type: "invalid_request_error", code: code, message: message}})
  end

  defp translate_error({msg, opts}) do
    Enum.reduce(opts, msg, fn
      {:count, n}, acc -> String.replace(acc, "%{count}", to_string(n))
      {key, val}, acc -> String.replace(acc, "%{#{key}}", to_string(val))
    end)
  end
end
