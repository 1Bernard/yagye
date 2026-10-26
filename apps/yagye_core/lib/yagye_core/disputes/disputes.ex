defmodule YagyeCore.Disputes do
  @moduledoc false

  require OpenTelemetry.Tracer

  require Logger

  alias Ecto.Multi
  alias YagyeCore.Checkout.Schemas.MerchantCheckoutConfig
  alias YagyeCore.Disputes.Schemas.{Dispute, Refund}
  alias YagyeCore.Disputes.Workers.RefundDispatchWorker
  alias YagyeCore.Ledger
  alias YagyeCore.Merchants.Schemas.Merchant
  alias YagyeCore.Outbox
  alias YagyeCore.Payments.Schemas.{Payment, PaymentAttempt, PaymentEvent}
  alias YagyeCore.Pricing
  alias YagyeCore.Repo
  alias YagyeCore.Reserves
  alias YagyeCore.Reserves.Schemas.ReserveHold
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

  Accepts payments in `succeeded`, `authorised`, `disputed`, or `partially_refunded` state.
  If the payment is `disputed`, the open dispute is retracted atomically.

  Applies the merchant's refund policy (window, partial support, approval threshold).
  Refunds above the merchant's `requires_approval_above_pesewas` threshold are created
  in `pending_approval` state and do NOT dispatch until `approve_refund/2` is called.

  Transitions payment:
    - partial refund (amount < payment.amount) → `partially_refunded`
    - full refund                               → `refunded`

  Ledger reversal is posted for `succeeded` / `partially_refunded` payments only
  (authorised = pre-settlement, no ledger entry exists yet to reverse).
  """
  def create_refund(%Payment{} = payment, attrs) do
    config = fetch_refund_config(payment.merchant_id)
    amount = attrs[:amount]

    with :ok <- validate_refundable(payment, config),
         :ok <- validate_partial_refunds(payment, amount, config),
         :ok <- validate_refund_amount(payment, amount),
         :ok <- validate_merchant_balance(payment, amount || payment.amount) do
      do_create_refund(payment, attrs, config)
    end
  end

  @doc """
  Approves a refund that is in `pending_approval` state.

  SoD constraint: `approved_by` must differ from `refund.initiated_by`.
  On approval the refund transitions to `requested` and the dispatch worker is enqueued.
  """
  def approve_refund(refund, approved_by, reason \\ nil)

  def approve_refund(%Refund{state: "pending_approval"} = refund, approved_by, reason) do
    Multi.new()
    |> Multi.update(:refund, Refund.approve_changeset(refund, approved_by, reason))
    |> Multi.update(:dispatch_state, fn %{refund: r} -> Refund.dispatch_changeset(r) end)
    |> Multi.insert(:dispatch_job, fn %{refund: r} ->
      RefundDispatchWorker.new(%{"refund_id" => r.id})
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{refund: r}} -> {:ok, r}
      {:error, :refund, %Ecto.Changeset{} = cs, _} -> {:error, cs}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  def approve_refund(%Refund{state: state}, _approved_by, _reason) do
    {:error, {:not_approvable, state}}
  end

  @doc """
  Rejects a refund that is in `pending_approval` state.

  SoD constraint: `rejected_by` must differ from `refund.initiated_by` (checked by convention;
  no DB constraint fires on rejection since `approved_by` stays nil).
  """
  def reject_refund(%Refund{state: "pending_approval"} = refund, rejected_by, reason) do
    refund
    |> Refund.reject_changeset(rejected_by, reason)
    |> Repo.update()
  end

  def reject_refund(%Refund{state: state}, _rejected_by, _reason) do
    {:error, {:not_rejectable, state}}
  end

  def get_pending_approval_refunds(opts \\ []) do
    base = from(r in Refund, where: r.state == "pending_approval", preload: [:payment])
    {:ok, Pagination.paginate(base, :public_id, opts)}
  end

  def list_disputes(merchant_id, opts \\ []) do
    base = from(d in Dispute, where: d.merchant_id == ^merchant_id)
    {:ok, Pagination.paginate(base, :public_id, opts)}
  end

  def list_refunds(merchant_id, opts \\ []) do
    base = from(r in Refund, where: r.merchant_id == ^merchant_id)
    {:ok, Pagination.paginate(base, :public_id, opts)}
  end

  @doc """
  Advances a dispute to `under_review` when a merchant submits evidence.
  No-ops if the dispute is already resolved.
  """
  def submit_evidence(%Dispute{stage: "resolved"} = dispute), do: {:ok, dispute}

  def submit_evidence(%Dispute{} = dispute) do
    with {:ok, updated} <-
           dispute
           |> Dispute.advance_stage_changeset("under_review")
           |> Repo.update() do
      payment = Repo.get!(Payment, updated.payment_id)

      Outbox.emit(
        payment,
        "dispute.evidence_submitted",
        %{
          public_id: updated.public_id,
          payment_id: payment.public_id,
          merchant_code: merchant_code(payment.merchant_id),
          amount: updated.amount,
          currency: updated.currency,
          reason: updated.reason,
          network: updated.network,
          stage: updated.stage,
          mode: payment.mode
        },
        correlation_id: updated.public_id
      )

      {:ok, updated}
    end
  end

  @doc """
  Auto-escalates an overdue dispute: resolves it with outcome `lost`.
  Called by DisputeEscalationWorker for disputes past their evidence_due_at deadline.
  Idempotent — no-ops if already resolved.
  """
  def auto_escalate(%Dispute{stage: "resolved"} = dispute), do: {:ok, dispute}

  def auto_escalate(%Dispute{} = dispute) do
    resolve_dispute(dispute, :lost)
  end

  @doc """
  Retracts a dispute when the card network signals withdrawal.
  Resolves the dispute with outcome `retracted`, transitioning the payment to `refunded`.
  No-ops if already resolved.
  """
  def retract_dispute(%Dispute{stage: "resolved"} = dispute), do: {:ok, dispute}

  def retract_dispute(%Dispute{} = dispute) do
    resolve_dispute(dispute, :retracted)
  end

  @doc """
  Finds the open dispute for a payment, if any.
  Returns `{:ok, dispute}` or `{:error, :not_found}`.
  """
  def find_open_dispute_for_payment(payment_id) do
    case Repo.one(
           from d in Dispute,
             where: d.payment_id == ^payment_id and d.stage != "resolved",
             limit: 1
         ) do
      nil -> {:error, :not_found}
      dispute -> {:ok, dispute}
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

  def get_refund_by_id(id) do
    case Repo.get(Refund, id) do
      nil -> {:error, :not_found}
      refund -> {:ok, refund}
    end
  end

  def settle_refund(refund, provider_ref \\ nil, provider_response \\ nil)

  def settle_refund(%Refund{state: "requested"} = refund, provider_ref, provider_response) do
    refund |> Refund.settle_changeset(provider_ref, provider_response) |> Repo.update()
  end

  def settle_refund(%Refund{state: state}, _provider_ref, _provider_response),
    do: {:ok, :already_in_state, state}

  def fail_refund(%Refund{state: "requested"} = refund, reason) do
    refund |> Refund.fail_changeset(reason) |> Repo.update()
  end

  def fail_refund(%Refund{state: state}, _reason), do: {:ok, :already_in_state, state}

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
    |> Multi.insert(:payment_outbox, fn %{payment: p, dispute: d} ->
      Outbox.build_changeset(
        p,
        "payment.disputed",
        %{
          public_id: p.public_id,
          state: p.state,
          merchant_code: merchant_code(p.merchant_id),
          amount: p.amount,
          currency: p.currency,
          method: p.method,
          mode: p.mode,
          dispute_id: d.public_id
        },
        correlation_id: p.public_id
      )
    end)
    |> Multi.insert(:dispute_outbox, fn %{payment: p, dispute: d} ->
      Outbox.build_changeset(
        p,
        "dispute.opened",
        %{
          dispute_id: d.public_id,
          payment_id: p.public_id,
          merchant_code: merchant_code(p.merchant_id),
          reference: d.public_id,
          payment_reference: p.public_id,
          amount: d.amount,
          currency: d.currency,
          reason: d.reason,
          network: d.network,
          status: "open",
          opened_at: DateTime.to_iso8601(DateTime.utc_now()),
          mode: p.mode
        },
        correlation_id: d.public_id
      )
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
    |> Multi.run(:ledger, fn _repo, %{transitioned_payment: p} ->
      if outcome == :lost, do: post_chargeback_ledger(p, dispute), else: {:ok, :no_ledger}
    end)
    |> Multi.run(:draw_reserve, fn _repo, %{dispute: d, transitioned_payment: p} ->
      draw_reserve_if_lost(outcome, p, d.id)
    end)
    |> Multi.insert(:dispute_outbox, fn %{dispute: d, transitioned_payment: p} ->
      Outbox.build_changeset(
        p,
        "dispute.resolved",
        %{
          dispute_id: d.public_id,
          payment_id: p.public_id,
          merchant_code: merchant_code(p.merchant_id),
          reference: d.public_id,
          payment_reference: p.public_id,
          amount: d.amount,
          currency: d.currency,
          reason: d.reason,
          status: d.outcome,
          resolved_at: d.resolved_at && DateTime.to_iso8601(d.resolved_at),
          payment_state: p.state,
          mode: p.mode
        },
        correlation_id: d.public_id
      )
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{dispute: dispute, transitioned_payment: payment}} -> {:ok, {dispute, payment}}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  defp do_create_refund(payment, attrs, config) do
    prior_state = payment.state
    amount = attrs[:amount] || payment.amount
    is_partial = amount < payment.amount
    needs_approval = requires_approval?(amount, config)
    # Authorised payments haven't been settled — window doesn't apply.
    window_check =
      if prior_state == "authorised", do: :ok, else: validate_refundable_window(payment, config)

    with :ok <- window_check do
      initial_state = if needs_approval, do: "pending_approval", else: "requested"
      next_payment_state = if is_partial, do: "partially_refunded", else: "refunded"
      event_type = if is_partial, do: "payment.partially_refunded", else: "payment.refunded"

      run_refund_multi(payment, attrs, %{
        amount: amount,
        prior_state: prior_state,
        initial_state: initial_state,
        next_payment_state: next_payment_state,
        event_type: event_type,
        is_partial: is_partial,
        needs_approval: needs_approval
      })
    end
  end

  defp draw_reserve_if_lost(:lost, payment, dispute_id) do
    hold =
      Repo.one(
        from h in ReserveHold,
          where: h.payment_id == ^payment.id and h.state == "pending",
          limit: 1
      )

    case hold do
      nil -> {:ok, :no_hold}
      h -> Reserves.draw_hold(h, dispute_id)
    end
  end

  defp draw_reserve_if_lost(_outcome, _payment, _dispute_id), do: {:ok, :no_draw}

  # Full refund: release pending reserve hold immediately — no dispute risk remains.
  # Partial refund: leave the hold; it releases on schedule at release_at.
  defp maybe_release_reserve_on_full_refund(_payment_id, true), do: {:ok, :partial_refund}

  defp maybe_release_reserve_on_full_refund(payment_id, false) do
    payment_id
    |> Reserves.holds_for_payment()
    |> Enum.find(&(&1.state == "pending"))
    |> case do
      nil -> {:ok, :no_hold}
      hold -> Reserves.release_hold(hold)
    end
  end

  defp run_refund_multi(payment, attrs, %{
         amount: amount,
         prior_state: prior_state,
         initial_state: initial_state,
         next_payment_state: next_payment_state,
         event_type: event_type,
         is_partial: is_partial,
         needs_approval: needs_approval
       }) do
    Multi.new()
    |> Multi.run(:lock_and_validate_amount, fn repo, _changes ->
      # Lock the payment row to prevent concurrent over-refund races,
      # then re-validate the remaining refundable amount.
      repo.one(from p in Payment, where: p.id == ^payment.id, lock: "FOR UPDATE")
      validate_refund_amount_locked(payment.id, amount, payment.amount)
    end)
    |> Multi.run(:dispute_or_nil, fn _repo, _changes ->
      dispute = if prior_state == "disputed", do: open_dispute_for(payment), else: nil
      {:ok, dispute}
    end)
    |> Multi.run(:refund, fn _repo, %{dispute_or_nil: dispute} ->
      insert_refund(payment, dispute, Map.put(attrs, :state, initial_state))
    end)
    |> Multi.run(:retract_dispute, fn _repo, %{dispute_or_nil: dispute} ->
      maybe_retract_dispute(dispute)
    end)
    |> Multi.run(:payment, fn _repo, _changes ->
      transition_payment(payment, next_payment_state)
    end)
    |> Multi.run(:increment_refunded_amount, fn _repo, _changes ->
      {1, _} =
        Repo.update_all(
          from(p in Payment, where: p.id == ^payment.id),
          inc: [refunded_amount: amount]
        )

      {:ok, :incremented}
    end)
    |> Multi.run(:event, fn _repo, %{payment: p} ->
      insert_payment_event(p, event_type, prior_state, next_payment_state)
    end)
    |> Multi.run(:ledger, fn _repo, %{payment: p, refund: r} ->
      post_ledger_reversal_if_settled(p, r, prior_state)
    end)
    |> Multi.run(:fee_reversal, fn _repo, %{refund: refund, payment: p} ->
      try_reverse_fee(p, refund)
    end)
    |> Multi.run(:release_reserve, fn _repo, _changes ->
      maybe_release_reserve_on_full_refund(payment.id, is_partial)
    end)
    |> Multi.insert(:outbox, fn %{payment: p} ->
      Outbox.build_changeset(
        p,
        event_type,
        %{
          public_id: p.public_id,
          state: p.state,
          merchant_code: merchant_code(p.merchant_id),
          amount: p.amount,
          refund_amount: amount,
          refunded_amount: p.refunded_amount + amount,
          currency: p.currency,
          method: p.method,
          mode: p.mode,
          prior_state: prior_state,
          pending_approval: needs_approval
        },
        correlation_id: p.public_id
      )
    end)
    |> Multi.run(:dispatch, fn _repo, %{refund: r} ->
      if needs_approval do
        # No dispatch yet — waiting for ops approval.
        {:ok, :pending_approval}
      else
        %{"refund_id" => r.id}
        |> RefundDispatchWorker.new()
        |> Oban.insert()
      end
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{refund: refund, payment: payment}} ->
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

  defp validate_refundable(%Payment{state: state}, _config)
       when state in ~w[succeeded authorised disputed partially_refunded],
       do: :ok

  defp validate_refundable(%Payment{state: state}, _config),
    do: {:error, {:not_refundable, state}}

  # Window check is separate from state check and runs inside do_create_refund
  # after state is validated, using the full payment struct (inserted_at).
  defp validate_refundable_window(%Payment{inserted_at: inserted_at}, %MerchantCheckoutConfig{
         refund_window_days: days
       }) do
    cutoff = DateTime.add(inserted_at, days * 86_400, :second)

    if DateTime.compare(DateTime.utc_now(), cutoff) == :gt do
      {:error, :window_expired}
    else
      :ok
    end
  end

  defp validate_refundable_window(_payment, nil), do: :ok

  defp validate_partial_refunds(_payment, nil, _config), do: {:error, :amount_required}

  defp validate_partial_refunds(payment, amount, %MerchantCheckoutConfig{
         partial_refunds_enabled: false
       })
       when amount < payment.amount do
    {:error, :partial_refunds_disabled}
  end

  defp validate_partial_refunds(_payment, _amount, _config), do: :ok

  defp validate_refund_amount(_payment, nil), do: {:error, :amount_required}

  defp validate_refund_amount(_payment, amount) when amount <= 0,
    do: {:error, :amount_exceeds_original}

  defp validate_refund_amount(payment, amount) do
    # Quick pre-check against the denormalized counter.
    # Authoritative race-safe check runs inside do_create_refund under a payment row lock.
    if payment.refunded_amount + amount <= payment.amount do
      :ok
    else
      {:error, :amount_exceeds_original}
    end
  end

  defp validate_refund_amount_locked(payment_id, amount, original_amount) do
    # Sum existing active refunds inside the transaction (payment row already locked).
    raw =
      Repo.one(
        from r in Refund,
          where:
            r.payment_id == ^payment_id and
              r.state in ["pending_approval", "approved", "requested", "succeeded"],
          select: coalesce(sum(r.amount), 0)
      )

    already_refunded =
      case raw do
        %Decimal{} = d -> Decimal.to_integer(d)
        n when is_integer(n) -> n
        _ -> 0
      end

    if already_refunded + amount <= original_amount do
      {:ok, already_refunded}
    else
      {:error, :amount_exceeds_original}
    end
  end

  defp validate_merchant_balance(payment, amount) do
    {:ok, balance} =
      Ledger.merchant_payable_balance(payment.merchant_id, payment.currency, payment.mode)

    cond do
      # No ledger account means merchant hasn't been settled yet — Yagye still holds
      # the funds, so the refund is safe.
      is_nil(balance) -> :ok
      balance >= amount -> :ok
      true -> {:error, :insufficient_balance}
    end
  end

  defp fetch_refund_config(merchant_id) do
    Repo.get(MerchantCheckoutConfig, merchant_id)
  end

  defp requires_approval?(amount, %MerchantCheckoutConfig{
         requires_approval_above_pesewas: threshold
       })
       when is_integer(threshold) and amount > threshold,
       do: true

  defp requires_approval?(_amount, _config), do: false

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

    state = attrs[:state] || "requested"

    %Refund{}
    |> Refund.changeset(%{
      payment_id: payment.id,
      merchant_id: payment.merchant_id,
      dispute_id: dispute && dispute.id,
      amount: attrs[:amount] || payment.amount,
      currency: payment.currency,
      reason: reason,
      state: state,
      initiated_by: attrs[:initiated_by],
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
  defp try_reverse_fee(payment, refund) do
    case find_succeeded_attempt(payment.id) do
      {:ok, attempt} -> attempt_fee_reversal(attempt, payment, refund)
      {:error, _} -> {:ok, :fee_reversal_skipped}
    end
  end

  defp attempt_fee_reversal(attempt, payment, refund) do
    case Pricing.reverse_fee(attempt.id, payment.merchant_id, refund.id, refund.amount) do
      {:ok, _} = ok ->
        ok

      {:error, reason} ->
        Logger.warning("fee reversal failed for refund #{refund.id}: #{inspect(reason)}")
        {:ok, :fee_reversal_skipped}
    end
  end

  defp post_ledger_reversal_if_settled(payment, refund, prior_state)
       when prior_state in ["succeeded", "partially_refunded"] do
    case find_succeeded_attempt(payment.id) do
      {:ok, attempt} -> Ledger.post_refund(payment, attempt, refund)
      {:error, :no_settled_attempt} -> {:ok, :skipped}
    end
  end

  defp post_ledger_reversal_if_settled(_payment, _refund, _prior_state), do: {:ok, :skipped}

  defp post_chargeback_ledger(payment, dispute) do
    case find_succeeded_attempt(payment.id) do
      {:ok, attempt} -> Ledger.post_chargeback(payment, attempt, dispute)
      {:error, :no_settled_attempt} -> {:ok, :skipped}
    end
  end

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

  defp merchant_code(merchant_id) do
    case Repo.get(Merchant, merchant_id) do
      %Merchant{public_id: code} -> code
      nil -> nil
    end
  end
end
