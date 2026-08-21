defmodule Simulator.Web.Controllers.NameEnquiryController do
  use Phoenix.Controller, formats: [:json]

  alias Simulator.Charges

  def create(conn, params) do
    account = conn.assigns.current_account

    with :ok <- require_param(params, "network"),
         :ok <- require_param(params, "msisdn"),
         :ok <- validate_network(params["network"]) do
      attrs = %{
        network: params["network"],
        msisdn: params["msisdn"],
        charge_id: params["charge_id"],
        delay_ms: params["delay_ms"] || 200
      }

      case Charges.name_enquiry(account, attrs) do
        {:ok, enquiry} ->
          json(conn, %{
            outcome: enquiry.outcome,
            account_name: enquiry.account_name,
            network: enquiry.network,
            msisdn: enquiry.msisdn,
            queried_at: enquiry.queried_at
          })

        {:error, reason} ->
          conn |> put_status(422) |> json(%{error: inspect(reason)})
      end
    else
      {:error, msg} ->
        conn |> put_status(422) |> json(%{error: "validation_error", message: msg})
    end
  end

  defp require_param(params, key) do
    if Map.get(params, key) in [nil, ""],
      do: {:error, "#{key} is required"},
      else: :ok
  end

  defp validate_network(n) when n in ~w[MTN TELECEL AIRTELTIGO], do: :ok
  defp validate_network(_), do: {:error, "network must be MTN, TELECEL, or AIRTELTIGO"}
end
