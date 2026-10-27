defmodule YagyeCoreWeb.Controllers.Internal.PayoutsController do
  @moduledoc """
  Internal endpoint for portal ops → Core payout creation.
  Uses service-token auth — ops staff can initiate a payout on a merchant's behalf
  after reviewing the payout request (maker-checker enforced in the portal).
  """

  use YagyeCoreWeb, :controller

  import Ecto.Query

  alias YagyeCore.Merchants
  alias YagyeCore.Payouts
  alias YagyeCore.Payouts.Schemas.PayoutDestination
  alias YagyeCore.Repo

  action_fallback YagyeCoreWeb.FallbackController

  def create(conn, %{"merchant_code" => merchant_code} = params) do
    with {:ok, merchant} <- Merchants.get_merchant(merchant_code),
         {:ok, destination} <- resolve_destination(merchant.id, params),
         {:ok, payout} <-
           Payouts.create_payout(merchant.id, build_attrs(params, merchant, destination)) do
      conn
      |> put_status(201)
      |> json(%{
        id: payout.public_id,
        state: payout.state,
        amount: payout.amount,
        currency: payout.currency,
        mode: payout.mode,
        destination_type: payout.destination_type
      })
    else
      {:error, :not_found} ->
        conn
        |> put_status(404)
        |> json(%{error: %{code: "not_found", message: "Merchant or destination not found"}})

      {:error, :no_verified_destination} ->
        conn
        |> put_status(422)
        |> json(%{
          error: %{
            code: "no_verified_destination",
            message: "Merchant has no verified payout destination"
          }
        })

      {:error, %Ecto.Changeset{} = cs} ->
        conn
        |> put_status(422)
        |> json(%{error: %{code: "validation_error", message: changeset_errors(cs)}})

      {:error, reason} ->
        conn |> put_status(422) |> json(%{error: %{code: to_string(reason)}})
    end
  end

  defp resolve_destination(merchant_id, %{"destination_id" => dest_public_id})
       when is_binary(dest_public_id) and dest_public_id != "" do
    case Repo.get_by(PayoutDestination,
           public_id: dest_public_id,
           merchant_id: merchant_id,
           active: true,
           verification_state: "verified"
         ) do
      nil -> {:error, :not_found}
      dest -> {:ok, dest}
    end
  end

  defp resolve_destination(merchant_id, _params) do
    case Repo.one(
           from d in PayoutDestination,
             where:
               d.merchant_id == ^merchant_id and d.active == true and
                 d.verification_state == "verified" and d.is_default == true,
             limit: 1
         ) ||
           Repo.one(
             from d in PayoutDestination,
               where:
                 d.merchant_id == ^merchant_id and d.active == true and
                   d.verification_state == "verified",
               order_by: [asc: :inserted_at],
               limit: 1
           ) do
      nil -> {:error, :no_verified_destination}
      dest -> {:ok, dest}
    end
  end

  defp build_attrs(params, merchant, destination) do
    %{
      merchant_id: merchant.id,
      destination_id: destination.id,
      destination_type: destination.kind,
      destination_fingerprint: destination.fingerprint,
      amount: parse_amount(params["amount"]),
      currency: params["currency"] || destination.currency || "GHS",
      mode: params["mode"] || "simulation",
      scheduled_for: Date.utc_today(),
      requested_by: params["requested_by"],
      approved_by: params["approved_by"]
    }
  end

  defp parse_amount(nil), do: nil
  defp parse_amount(val) when is_integer(val), do: val
  defp parse_amount(val), do: String.to_integer(to_string(val))

  defp changeset_errors(%Ecto.Changeset{} = cs) do
    Ecto.Changeset.traverse_errors(cs, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map_join("; ", fn {field, errors} -> "#{field}: #{Enum.join(errors, ", ")}" end)
  end
end
