defmodule YagyeCore.Payments do
  @moduledoc false

  alias YagyeCore.Payments.Schemas.{Payment, PaymentEvent}
  alias YagyeCore.Payments.Workers.PaymentDispatchWorker
  alias YagyeCore.Merchants.Schemas.Merchant
  alias YagyeCore.Repo

  # ── Public API ───────────────────────────────────────────────────────────────

  def create_payment(merchant_id, attrs) do
    with {:ok, {payment, event}} <- insert_payment(merchant_id, attrs),
         {:ok, _job} <- PaymentDispatchWorker.new(%{payment_id: payment.id}) |> Oban.insert() do
      {:ok, {payment, event}}
    end
  end

  defp insert_payment(merchant_id, attrs) do
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

  def dispatch_payment(payment_id) do
    do_transition(payment_id, "created", "processing")
  end

  def simulate_payment(payment_id) do
    with {:ok, payment} <- do_transition(payment_id, "processing", "authorised"),
         {:ok, payment} <- do_transition(payment.id, "authorised", "succeeded") do
      {:ok, payment}
    end
  end

  def get_payment(public_id) do
    case Repo.get_by(Payment, public_id: public_id) do
      nil -> {:error, :not_found}
      payment -> {:ok, payment}
    end
  end

  def list_events(payment_id) do
    import Ecto.Query

    events =
      from(e in PaymentEvent,
        where: e.payment_id == ^payment_id,
        order_by: [asc: e.version]
      )
      |> Repo.all()

    {:ok, events}
  end

  # ── Private ──────────────────────────────────────────────────────────────────

  defp do_transition(payment_id, from_state, to_state) do
    Repo.transaction(fn ->
      with {:ok, payment} <- get_payment_by_id(payment_id),
           {:ok, payment} <- transition(payment, to_state),
           {:ok, _event} <- insert_event(payment, "payment.#{to_state}", from_state, to_state) do
        payment
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp get_payment_by_id(id) do
    case Repo.get(Payment, id) do
      nil -> {:error, :not_found}
      payment -> {:ok, payment}
    end
  end

  defp transition(payment, to_state) do
    payment
    |> Payment.transition_changeset(to_state)
    |> Repo.update()
  end

  defp resolve_merchant(merchant_id) do
    case Repo.get(Merchant, merchant_id) do
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
