defmodule YagyeCore.Disputes do
  @moduledoc false

  alias YagyeCore.Disputes.Schemas.{Dispute, Refund}
  alias YagyeCore.Ledger
  alias YagyeCore.Payments.Schemas.{Payment, PaymentAttempt, PaymentEvent}
  alias YagyeCore.Repo

  import Ecto.Query

  # ── Public API ───────────────────────────────────────────────────────────────

  @doc """
  Opens a dispute for a payment. The payment must be in the `succeeded` state.
  Transitions payment → `disputed` and records a payment event.
  """
  def create_dispute(%Payment{} = payment, attrs) do
    with :ok <- validate_disputable(payment), do: do_create_dispute(payment, attrs)
  end

  @doc """
  Resolves an open dispute. Outcome must be :won, :lost, or :retracted.

  - :won  → payment transitions back to `succeeded`
  - :lost → payment transitions to `chargebacked`
  - :retracted → payment transitions to `refunded` (called internally by create_refund)
  """
  def resolve_dispute(%Dispute{} = dispute, outcome) when outcome in [:won, :lost, :retracted] do
    with :ok <- validate_resolvable(dispute), do: do_resolve_dispute(dispute, outcome)
  end

  @doc """
  Issues a refund for a payment.

  Accepts payments in `succeeded`, `authorised`, or `disputed` state.
  If the payment is `disputed`, the open dispute is retracted atomically.
  Transitions payment → `refunded`.

  Ledger reversal is posted for `succeeded` payments only (authorised = pre-settlement,
  no ledger entry exists yet to reverse).
  """
  def create_refund(%Payment{} = payment, attrs) do
    with :ok <- validate_refundable(payment),
         :ok <- validate_refund_amount(payment, attrs[:amount]) do
      do_create_refund(payment, attrs)
    end
  end

  def get_dispute(public_id) do
    case Repo.get_by(Dispute, public_id: public_id) do
      nil -> {:error, :not_found}
      dispute -> {:ok, dispute}
    end
  end

  def get_refund(public_id) do
    case Repo.get_by(Refund, public_id: public_id) do
      nil -> {:error, :not_found}
      refund -> {:ok, Repo.preload(refund, :dispute)}
    end
  end

  # ── Transaction bodies ───────────────────────────────────────────────────────

  defp do_create_dispute(payment, attrs) do
    Repo.transaction(fn ->
      with {:ok, dispute} <- insert_dispute(payment, attrs),
           {:ok, payment} <- transition_payment(payment, "disputed"),
           {:ok, _event} <-
             insert_payment_event(payment, "payment.disputed", "succeeded", "disputed") do
        {dispute, payment}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp do_resolve_dispute(dispute, outcome) do
    outcome_str = Atom.to_string(outcome)
    to_state = payment_state_for_outcome(outcome)

    Repo.transaction(fn ->
      payment = Repo.get!(Payment, dispute.payment_id)

      with {:ok, dispute} <- dispute |> Dispute.resolve_changeset(outcome_str) |> Repo.update(),
           {:ok, payment} <- transition_payment(payment, to_state),
           {:ok, _event} <-
             insert_payment_event(payment, "payment.#{to_state}", "disputed", to_state) do
        {dispute, payment}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp do_create_refund(payment, attrs) do
    prior_state = payment.state

    Repo.transaction(fn ->
      dispute = if prior_state == "disputed", do: open_dispute_for(payment), else: nil

      with {:ok, refund} <- insert_refund(payment, dispute, attrs),
           {:ok, refund} <- refund |> Refund.settle_changeset() |> Repo.update(),
           {:ok, _} <- maybe_retract_dispute(dispute),
           {:ok, payment} <- transition_payment(payment, "refunded"),
           {:ok, _event} <-
             insert_payment_event(payment, "payment.refunded", prior_state, "refunded"),
           :ok <- maybe_post_ledger_reversal(payment, refund) do
        {Repo.preload(refund, :dispute), payment}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  # ── Validation ───────────────────────────────────────────────────────────────

  defp validate_disputable(%Payment{state: "succeeded"}), do: :ok
  defp validate_disputable(%Payment{state: state}), do: {:error, {:not_disputable, state}}

  defp validate_resolvable(%Dispute{stage: "resolved"}), do: {:error, :already_resolved}
  defp validate_resolvable(_), do: :ok

  defp validate_refundable(%Payment{state: state})
       when state in ~w[succeeded authorised disputed],
       do: :ok

  defp validate_refundable(%Payment{state: state}), do: {:error, {:not_refundable, state}}

  defp validate_refund_amount(_payment, nil), do: {:error, :amount_required}

  defp validate_refund_amount(payment, amount) do
    max = payment.amount

    if amount > 0 and amount <= max do
      :ok
    else
      {:error, :amount_exceeds_original}
    end
  end

  # ── Helpers ──────────────────────────────────────────────────────────────────

  defp insert_dispute(payment, attrs) do
    base = %{
      payment_id: payment.id,
      merchant_id: payment.merchant_id,
      currency: payment.currency,
      amount: payment.amount
    }

    overrides = Map.reject(attrs, fn {_k, v} -> is_nil(v) end)

    %Dispute{}
    |> Dispute.changeset(Map.merge(base, overrides))
    |> Repo.insert()
  end

  defp insert_refund(payment, dispute, attrs) do
    reason =
      if dispute do
        "dispute_retracted"
      else
        attrs[:reason] || "customer_request"
      end

    %Refund{}
    |> Refund.changeset(%{
      payment_id: payment.id,
      merchant_id: payment.merchant_id,
      dispute_id: dispute && dispute.id,
      amount: attrs.amount,
      currency: payment.currency,
      reason: reason,
      metadata: attrs[:metadata] || %{}
    })
    |> Repo.insert()
  end

  defp open_dispute_for(payment) do
    Repo.one!(
      from d in Dispute,
        where: d.payment_id == ^payment.id and d.stage != "resolved",
        limit: 1
    )
  end

  defp maybe_retract_dispute(nil), do: {:ok, nil}

  defp maybe_retract_dispute(%Dispute{} = dispute) do
    dispute
    |> Dispute.resolve_changeset("retracted")
    |> Repo.update()
  end

  defp maybe_post_ledger_reversal(%Payment{state: "succeeded"} = payment, refund) do
    case find_succeeded_attempt(payment.id) do
      {:ok, attempt} -> Ledger.post_refund(payment, attempt, refund)
      {:error, :no_settled_attempt} -> :ok
    end
  end

  defp maybe_post_ledger_reversal(_payment, _refund), do: :ok

  defp find_succeeded_attempt(payment_id) do
    case Repo.one(
           from a in PaymentAttempt,
             where: a.payment_id == ^payment_id and a.state == "succeeded",
             limit: 1
         ) do
      nil -> {:error, :no_settled_attempt}
      attempt -> {:ok, attempt}
    end
  end

  defp transition_payment(payment, to_state) do
    payment |> Payment.transition_changeset(to_state) |> Repo.update()
  end

  defp insert_payment_event(payment, event_type, from_state, to_state) do
    now = DateTime.utc_now()

    %PaymentEvent{}
    |> PaymentEvent.changeset(%{
      payment_id: payment.id,
      version: payment.version,
      event_type: event_type,
      from_state: from_state,
      to_state: to_state,
      actor: "system",
      correlation_id: payment.public_id,
      occurred_at: now,
      recorded_at: now
    })
    |> Repo.insert()
  end

  defp payment_state_for_outcome(:won), do: "succeeded"
  defp payment_state_for_outcome(:lost), do: "chargebacked"
  defp payment_state_for_outcome(:retracted), do: "refunded"
end
