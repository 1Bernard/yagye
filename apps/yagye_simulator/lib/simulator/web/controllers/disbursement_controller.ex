defmodule Simulator.Web.Controllers.DisbursementController do
  @moduledoc false

  use Phoenix.Controller, formats: [:json]

  alias Simulator.Disbursements

  @doc """
  POST /disbursements

  Body: { amount_minor, currency, destination_type, destination_ref }

  Creates a disbursement for the authenticated account. In simulation mode it
  settles immediately and returns state PAID.
  """
  def create(conn, params) do
    account = conn.assigns.current_account

    attrs = %{
      amount_minor: params["amount_minor"],
      currency: params["currency"],
      destination_type: params["destination_type"],
      destination_ref: params["destination_ref"]
    }

    case Disbursements.create_disbursement(account, attrs) do
      {:ok, disbursement} ->
        conn
        |> put_status(201)
        |> json(%{
          disbursement_ref: disbursement.disbursement_ref,
          state: disbursement.state,
          amount_minor: disbursement.amount_minor,
          currency: disbursement.currency,
          destination_type: disbursement.destination_type,
          destination_ref: disbursement.destination_ref,
          paid_at: disbursement.paid_at && DateTime.to_iso8601(disbursement.paid_at)
        })

      {:error, changeset} ->
        conn
        |> put_status(422)
        |> json(%{error: "validation_failed", details: format_errors(changeset)})
    end
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
