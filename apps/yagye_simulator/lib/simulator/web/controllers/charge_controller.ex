defmodule Simulator.Web.Controllers.ChargeController do
  use Phoenix.Controller, formats: [:json]

  alias Simulator.Charges

  def create(conn, params) do
    account = conn.assigns.current_account

    attrs = %{
      amount_minor: params["amount_minor"],
      currency: params["currency"],
      instrument_type: params["instrument_type"] || "CARD",
      idempotency_key: params["idempotency_key"],
      scenario_id: params["scenario_id"],
      seed: params["seed"],
      # Wallet-specific
      network: params["network"],
      msisdn: params["msisdn"],
      approval_delay_ms: params["approval_delay_ms"]
    }

    case validate_create_params(attrs) do
      :ok ->
        case Charges.create_charge(account, attrs) do
          {:ok, charge} -> json(conn, render_charge(charge))
          {:error, reason} -> render_error(conn, reason)
        end

      {:error, message} ->
        conn |> put_status(422) |> json(%{error: "validation_error", message: message})
    end
  end

  def show(conn, %{"ref" => ref}) do
    case Charges.get_by_ref(ref) do
      {:ok, charge} -> json(conn, render_charge(charge))
      {:error, :not_found} -> conn |> put_status(404) |> json(%{error: "charge_not_found"})
    end
  end

  # ── Private ──────────────────────────────────────────────────────────────────

  defp validate_create_params(%{amount_minor: nil}),
    do: {:error, "amount_minor is required"}

  defp validate_create_params(%{amount_minor: a}) when not is_integer(a) or a <= 0,
    do: {:error, "amount_minor must be a positive integer"}

  defp validate_create_params(%{currency: nil}),
    do: {:error, "currency is required"}

  defp validate_create_params(%{instrument_type: t})
       when t not in ["CARD", "WALLET", "BANK"],
       do: {:error, "instrument_type must be CARD, WALLET, or BANK"}

  defp validate_create_params(_), do: :ok

  defp render_charge(charge) do
    base = %{
      charge_ref: charge.charge_ref,
      state: charge.state,
      amount_minor: charge.amount_minor,
      currency: charge.currency,
      instrument_type: charge.instrument_type,
      created_at: charge.created_at
    }

    case charge.state do
      "AUTHORISED" ->
        Map.merge(base, %{
          auth_code: charge.auth_code,
          rrn: charge.rrn,
          arn: charge.arn,
          authorised_at: charge.authorised_at
        })

      "DECLINED" ->
        Map.put(base, :decline_code, charge.decline_code)

      _ ->
        base
    end
  end

  defp render_error(conn, {:error, :charge_not_created}) do
    conn |> put_status(500) |> json(%{error: "charge_not_created"})
  end

  defp render_error(conn, reason) do
    conn |> put_status(422) |> json(%{error: inspect(reason)})
  end
end
