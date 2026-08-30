defmodule YagyeCore.Disputes do
  @moduledoc false

  require OpenTelemetry.Tracer

  alias Ecto.Multi
  alias YagyeCore.Disputes.Schemas.{Dispute, Refund}
  alias YagyeCore.Ledger
  alias YagyeCore.Outbox
  alias YagyeCore.Payments.Schemas.{Payment, PaymentAttempt, PaymentEvent}
  alias YagyeCore.Repo
  alias YagyeCore.Shared.Pagination

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

  def list_disputes(merchant_id, opts \\ []) do
    base = from(d in Dispute, where: d.merchant_id == ^merchant_id)
    {:ok, Pagination.paginate(base, :public_id, opts)}
  end

  def list_refunds(merchant_id, opts \\ []) do
    base = from(r in Refund, where: r.merchant_id == ^merchant_id)
    {:ok, Pagination.paginate(base, :public_id, opts)}
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
    Multi.new()
    |> Multi.run(:dispute, fn _repo, _changes ->
      insert_dispute(payment, attrs)
    end)
    |> Multi.run(:payment, fn _repo, _changes ->
      transition_payment(payment, "disputed")
    end)
    |> Multi.run(:event, fn _repo, %{payment: p} ->
      insert_payment_event(p, "payment.disputed", "succeeded", "disputed")
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{dispute: dispute, payment: payment}} -> {:ok, {dispute, payment}}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  defp do_resolve_dispute(dispute, outcome) do
    outcome_str = Atom.to_string(outcome)
    to_state = payment_state_for_outcome(outcome)

    Multi.new()
    |> Multi.run(:payment, fn _repo, _changes ->
      {:ok, Repo.get!(Payment, dispute.payment_id)}
    end)
    |> Multi.run(:dispute, fn _repo, _changes ->
      dispute |> Dispute.resolve_changeset(outcome_str) |> Repo.update()
    end)
    |> Multi.run(:transitioned_payment, fn _repo, %{payment: payment} ->
      transition_payment(payment, to_state)
    end)
    |> Multi.run(:event, fn _repo, %{transitioned_payment: p} ->
      insert_payment_event(p, "payment.#{to_state}", "disputed", to_state)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{dispute: dispute, transitioned_payment: payment}} -> {:ok, {dispute, payment}}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  defp do_create_refund(payment, attrs) do
    prior_state = payment.state

    Multi.new()
    |> Multi.run(:dispute_or_nil, fn _repo, _changes ->
      dispute = if prior_state == "disputed", do: open_dispute_for(payment), else: nil
      {:ok, dispute}
    end)
    |> Multi.run(:refund, fn _repo, %{dispute_or_nil: dispute} ->
      insert_refund(payment, dispute, attrs)
    end)
    |> Multi.run(:settled_refund, fn _repo, %{refund: refund} ->
      refund |> Refund.settle_changeset() |> Repo.update()
    end)
    |> Multi.run(:retract_dispute, fn _repo, %{dispute_or_nil: dispute} ->
      maybe_retract_dispute(dispute)
    end)
    |> Multi.run(:payment, fn _repo, _changes ->
      transition_payment(payment, "refunded")
    end)
    |> Multi.run(:event, fn _repo, %{payment: p} ->
      insert_payment_event(p, "payment.refunded", prior_state, "refunded")
    end)
    |> Multi.run(:ledger, fn _repo, %{payment: p, settled_refund: r} ->
      post_ledger_reversal_if_settled(p, r, prior_state)
    end)
    |> Multi.run(:outbox, fn _repo, %{payment: p} ->
      Outbox.emit(p, "payment.refunded", %{
        amount: attrs.amount,
        currency: p.currency,
        prior_state: prior_state
      })
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{settled_refund: refund, payment: payment}} ->
        {:ok, {Repo.preload(refund, :dispute), payment}}

      {:error, _step, reason, _changes} ->
        {:error, reason}
    end
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

  # Prior state is used as the guard, not payment.state, because payment is already
  # "refunded" at the point of this call (transitioned earlier in the same Multi).
  defp post_ledger_reversal_if_settled(payment, refund, "succeeded") do
    case find_succeeded_attempt(payment.id) do
      {:ok, attempt} -> Ledger.post_refund(payment, attempt, refund)
      {:error, :no_settled_attempt} -> {:ok, :skipped}
    end
  end

  defp post_ledger_reversal_if_settled(_payment, _refund, _prior_state), do: {:ok, :skipped}

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
      trace_id: current_trace_id(),
      occurred_at: now,
      recorded_at: now
    })
    |> Repo.insert()
  end

  defp current_trace_id do
    case OpenTelemetry.Tracer.current_span_ctx() do
      :undefined ->
        nil

      span_ctx ->
        trace_id = :otel_span.trace_id(span_ctx)

        if trace_id == 0,
          do: nil,
          else:
            trace_id |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(32, "0")
    end
  end

  defp payment_state_for_outcome(:won), do: "succeeded"
  defp payment_state_for_outcome(:lost), do: "chargebacked"
  defp payment_state_for_outcome(:retracted), do: "refunded"
end
