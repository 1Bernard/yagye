defmodule Simulator.Refunds do
  @moduledoc false

  alias Simulator.Charges
  alias Simulator.Refunds.Schemas.Refund
  alias Simulator.Repo

  # ── Public API ───────────────────────────────────────────────────────────────

  def create_refund(account, charge_ref, attrs) do
    with {:ok, charge} <- Charges.get_by_ref(charge_ref),
         :ok <- validate_refundable(charge, account),
         :ok <- validate_amount(charge, attrs.amount_minor) do
      insert_refund(charge, account, attrs)
    end
  end

  def get_by_ref(refund_ref) do
    case Repo.get_by(Refund, refund_ref: refund_ref) do
      nil -> {:error, :not_found}
      refund -> {:ok, refund}
    end
  end

  # ── Private ──────────────────────────────────────────────────────────────────

  defp validate_refundable(charge, account) do
    cond do
      charge.account_id != account.id ->
        {:error, :not_found}

      charge.state not in ~w[AUTHORISED CAPTURED PARTIALLY_CAPTURED] ->
        {:error, {:not_refundable, charge.state}}

      true ->
        :ok
    end
  end

  defp validate_amount(charge, refund_amount) do
    refundable = charge.authorised_amount_minor || charge.amount_minor

    if refund_amount > refundable do
      {:error, :amount_exceeds_original}
    else
      :ok
    end
  end

  defp insert_refund(charge, account, attrs) do
    %Refund{}
    |> Refund.changeset(%{
      charge_id: charge.id,
      account_id: account.id,
      refund_ref: "RF_" <> Uniq.UUID.uuid7(),
      amount_minor: attrs.amount_minor,
      currency: charge.currency,
      state: "OK",
      fee_minor: account.fee_fixed_minor
    })
    |> Repo.insert()
  end
end
