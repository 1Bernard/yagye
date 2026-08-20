defmodule YagyeCoreWeb.FallbackController do
  @moduledoc false

  use Phoenix.Controller, formats: [:json]

  alias YagyeCoreWeb.Response

  def call(conn, {:error, :not_found}), do: Response.not_found(conn)

  def call(conn, {:error, :invalid_state}),
    do:
      Response.unprocessable(
        conn,
        "invalid_state",
        "Resource is not in a state that allows this operation"
      )

  def call(conn, {:error, :invalid_onboarding_state}),
    do:
      Response.unprocessable(
        conn,
        "invalid_onboarding_state",
        "Onboarding is not in a submittable state"
      )

  def call(conn, {:error, changeset}), do: Response.validation_error(conn, changeset)
end
