defmodule YagyeCoreWeb.Controllers.Internal.PayoutDestinationsController do
  @moduledoc false

  use YagyeCoreWeb, :controller

  alias YagyeCore.Merchants
  alias YagyeCore.Payouts
  alias YagyeCore.Payouts.Schemas.PayoutDestination

  action_fallback YagyeCoreWeb.FallbackController

  def index(conn, %{"merchant_code" => code}) do
    with {:ok, merchant} <- Merchants.get_merchant(code) do
      destinations = Payouts.list_destinations(merchant.id)
      json(conn, %{object: "list", data: Enum.map(destinations, &serialize/1)})
    end
  end

  def create(conn, %{"merchant_code" => code} = params) do
    with {:ok, merchant} <- Merchants.get_merchant(code) do
      attrs = %{
        mode: params["mode"] || "live",
        kind: params["kind"],
        currency: params["currency"] || "GHS",
        account_details: params["account_details"],
        account_name_verified: params["account_name_verified"],
        added_by: params["added_by"]
      }

      case Payouts.create_destination(merchant.id, attrs) do
        {:ok, dest} ->
          conn |> put_status(201) |> json(serialize(dest))

        {:error, cs} ->
          conn |> put_status(422) |> json(%{errors: format_errors(cs)})
      end
    end
  end

  def set_default(conn, %{"merchant_code" => code, "id" => public_id}) do
    with {:ok, merchant} <- Merchants.get_merchant(code),
         {:ok, dest} <- Payouts.get_destination_by_public_id(public_id),
         true <- dest.merchant_id == merchant.id || {:error, :not_found},
         {:ok, updated} <- Payouts.set_default_destination(merchant.id, dest.id) do
      json(conn, serialize(updated))
    else
      false -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def deactivate(conn, %{"merchant_code" => code, "id" => public_id}) do
    with {:ok, merchant} <- Merchants.get_merchant(code),
         {:ok, dest} <- Payouts.get_destination_by_public_id(public_id),
         true <- dest.merchant_id == merchant.id || {:error, :not_found},
         {:ok, _} <- Payouts.deactivate_destination(dest) do
      json(conn, %{id: public_id, active: false})
    else
      false -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp serialize(%PayoutDestination{} = d) do
    details = masked_details(d)

    %{
      id: d.public_id,
      object: "payout_destination",
      kind: d.kind,
      mode: d.mode,
      currency: d.currency,
      verification_state: d.verification_state,
      is_default: d.is_default,
      account_name_verified: d.account_name_verified,
      added_by: d.added_by,
      verified_by: d.verified_by,
      inserted_at: d.inserted_at,
      updated_at: d.updated_at
    }
    |> Map.merge(details)
  end

  defp masked_details(%PayoutDestination{} = d) do
    case PayoutDestination.decrypt_details(d) do
      {:ok, details} ->
        case d.kind do
          "mobile_money" ->
            msisdn = details["msisdn"] || details["account_number"] || ""
            %{masked_account: mask_msisdn(msisdn), network: details["network"]}

          "bank" ->
            number = details["account_number"] || ""

            %{
              masked_account: mask_account_number(number),
              bank_code: details["bank_code"],
              account_name: details["account_name"]
            }

          _ ->
            %{}
        end

      _ ->
        %{}
    end
  end

  defp mask_msisdn(msisdn) when byte_size(msisdn) > 6 do
    prefix = String.slice(msisdn, 0, 3)
    suffix = String.slice(msisdn, -4, 4)
    "#{prefix} *** #{suffix}"
  end

  defp mask_msisdn(msisdn), do: msisdn

  defp mask_account_number(number) when byte_size(number) > 4 do
    "••••" <> String.slice(number, -4, 4)
  end

  defp mask_account_number(number), do: number

  defp format_errors(cs) do
    Ecto.Changeset.traverse_errors(cs, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc -> String.replace(acc, "%{#{k}}", to_string(v)) end)
    end)
  end
end
