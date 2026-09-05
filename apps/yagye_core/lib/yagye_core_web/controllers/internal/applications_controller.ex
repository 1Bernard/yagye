defmodule YagyeCoreWeb.Controllers.Internal.ApplicationsController do
  @moduledoc """
  Internal ops endpoints for KYB application disposition.
  Called by the Yagye Portal on behalf of ops staff.
  Protected by X-Service-Token (see AuthenticateInternal plug).
  """

  use YagyeCoreWeb, :controller

  alias YagyeCore.Merchants

  action_fallback YagyeCoreWeb.FallbackController

  def approve(conn, %{"application_id" => application_id} = params) do
    approved_by = Map.get(params, "approved_by", "portal")

    case Merchants.approve_application(application_id, approved_by) do
      {:ok, _result} ->
        json(conn, %{ok: true})

      {:error, :not_found} ->
        conn
        |> put_status(404)
        |> json(%{error: %{code: "not_found", message: "Application not found"}})

      {:error, :invalid_state} ->
        conn
        |> put_status(422)
        |> json(%{
          error: %{
            code: "invalid_state",
            message: "Application cannot be approved in its current state"
          }
        })

      {:error, reason} ->
        conn
        |> put_status(422)
        |> json(%{error: %{code: "unprocessable", message: inspect(reason)}})
    end
  end

  def reject(conn, %{"application_id" => application_id} = params) do
    rejected_by = Map.get(params, "rejected_by", "portal")
    reason = Map.get(params, "reason", "")

    if reason == "" do
      conn
      |> put_status(422)
      |> json(%{error: %{code: "validation_error", message: "reason is required"}})
    else
      case Merchants.reject_application(application_id, rejected_by, reason) do
        {:ok, _result} ->
          json(conn, %{ok: true})

        {:error, :not_found} ->
          conn
          |> put_status(404)
          |> json(%{error: %{code: "not_found", message: "Application not found"}})

        {:error, :invalid_state} ->
          conn
          |> put_status(422)
          |> json(%{
            error: %{
              code: "invalid_state",
              message: "Application cannot be rejected in its current state"
            }
          })

        {:error, reason} ->
          conn
          |> put_status(422)
          |> json(%{error: %{code: "unprocessable", message: inspect(reason)}})
      end
    end
  end
end
