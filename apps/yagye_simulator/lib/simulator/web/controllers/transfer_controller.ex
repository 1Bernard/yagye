defmodule Simulator.Web.Controllers.TransferController do
  @moduledoc """
  Simulates an inbound GhIPSS Instant Pay credit to a virtual account.
  Called from the Live Simulation page ("Simulate Transfer") or directly
  via the API to resolve a PENDING_AUTH BANK charge.

  POST /transfers
  Body: { "virtual_account_number": "074...", "amount_minor": 50000 }
        OR { "charge_ref": "gw_...", "amount_minor": 50000 }
  """

  use Phoenix.Controller, formats: [:json]

  alias Simulator.Charges
  alias Simulator.Webhooks

  def create(conn, params) do
    account = conn.assigns.current_account

    with {:ok, charge} <- find_charge(params),
         :ok <- validate_ownership(charge, account),
         {:ok, charge} <-
           Charges.authorise_bank_charge_by_va(
             charge.virtual_account_number,
             params["amount_minor"] || charge.amount_minor
           ) do
      case Webhooks.enqueue_delivery(account.id, charge.charge_ref, schedule_in: 1) do
        {:ok, _} ->
          json(conn, %{
            status: "transfer_received",
            charge_ref: charge.charge_ref,
            authorised_amount_minor: charge.amount_minor
          })

        {:error, reason} ->
          conn |> put_status(500) |> json(%{error: inspect(reason)})
      end
    else
      {:error, :not_found} ->
        conn |> put_status(404) |> json(%{error: "charge_not_found"})

      {:error, :wrong_account} ->
        conn |> put_status(403) |> json(%{error: "charge_belongs_to_different_account"})

      {:error, :not_bank_transfer} ->
        conn |> put_status(422) |> json(%{error: "charge_is_not_a_bank_transfer"})

      {:error, :not_pending} ->
        conn |> put_status(422) |> json(%{error: "charge_not_in_pending_state"})

      {:error, :amount_mismatch} ->
        conn |> put_status(422) |> json(%{error: "transfer_amount_does_not_match_charge"})
    end
  end

  # ── Private ──────────────────────────────────────────────────────────────────

  defp find_charge(%{"virtual_account_number" => va_number}) do
    Charges.find_pending_bank_by_va(va_number)
  end

  defp find_charge(%{"charge_ref" => charge_ref}) do
    case Charges.get_by_ref(charge_ref) do
      {:ok, %{instrument_type: "BANK", state: "PENDING_AUTH"} = charge} -> {:ok, charge}
      {:ok, %{instrument_type: type}} when type != "BANK" -> {:error, :not_bank_transfer}
      {:ok, _} -> {:error, :not_pending}
      err -> err
    end
  end

  defp find_charge(_params) do
    {:error, :not_found}
  end

  defp validate_ownership(charge, account) do
    if charge.account_id == account.id, do: :ok, else: {:error, :wrong_account}
  end
end
