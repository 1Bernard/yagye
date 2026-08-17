defmodule YagyeCoreWeb.Plugs.ValidationErrorRenderer do
  @moduledoc false

  # Custom render_error plug for OpenApiSpex.Plug.CastAndValidate.
  # Converts schema validation errors into our Stripe-style error envelope
  # instead of the default JSON:API format.
  #
  # Usage in controllers:
  #   plug OpenApiSpex.Plug.CastAndValidate,
  #     render_error: YagyeCoreWeb.Plugs.ValidationErrorRenderer

  @behaviour Plug

  alias OpenApiSpex.OpenApi
  alias Plug.Conn

  @impl Plug
  def init(errors), do: errors

  @impl Plug
  def call(conn, errors) when is_list(errors) do
    first = List.first(errors)

    body =
      OpenApi.json_encoder().encode!(%{
        error: %{
          type: "invalid_request_error",
          code: "schema_validation_failed",
          message: to_string(first),
          details: Enum.map(errors, &to_string/1)
        }
      })

    conn
    |> Conn.put_resp_content_type("application/json")
    |> Conn.send_resp(422, body)
  end
end
