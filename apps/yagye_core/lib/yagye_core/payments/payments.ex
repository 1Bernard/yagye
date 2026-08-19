defmodule YagyeCore.Payments do
  @moduledoc false

  alias YagyeCore.Payments.{Payment, PaymentEvent}
  alias YagyeCore.Merchants.Merchant
  alias YagyeCore.Repo

  # ── Public API ───────────────────────────────────────────────────────────────

  def create_payment(merchant_id, attrs) do
    Repo.transaction(fn ->
      with {:ok, merchant} <- resolve_merchant(merchant_id),
           attrs = Map.merge(attrs, %{merchant_id: merchant.id, mode: current_mode(merchant)}),
           {:ok, payment} <- %Payment{} |> Payment.changeset(attrs) |> Repo.insert(),
           {:ok, event} <- insert_event(payment, "payment.created", nil, "created") do
        {payment, event}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def get_payment(public_id) do
    case Repo.get_by(Payment, public_id: public_id) do
      nil -> {:error, :not_found}
      payment -> {:ok, payment}
    end
  end

  # ── Private ──────────────────────────────────────────────────────────────────

  defp resolve_merchant(public_id) do
    case Repo.get_by(Merchant, public_id: public_id) do
      nil -> {:error, :not_found}
      merchant -> {:ok, merchant}
    end
  end

  defp current_mode(merchant) do
    case YagyeCore.Merchants.live_mode_enabled?(merchant.id) do
      true -> "live"
      false -> "simulation"
    end
  end

  defp insert_event(payment, event_type, from_state, to_state) do
    now = DateTime.utc_now()

    %PaymentEvent{}
    |> PaymentEvent.changeset(%{
      payment_id:     payment.id,
      version:        payment.version,
      event_type:     event_type,
      from_state:     from_state,
      to_state:       to_state,
      actor:          "system",
      correlation_id: payment.public_id,
      occurred_at:    now,
      recorded_at:    now
    })
    |> Repo.insert()
  end
end
