defmodule YagyeCore.Escrow do
  @moduledoc false

  require Logger

  import Ecto.Query

  alias Ecto.Multi
  alias YagyeCore.Checkout.Schemas.CheckoutSession
  alias YagyeCore.Escrow.Schemas.{EscrowDisputeEvent, EscrowHold}
  alias YagyeCore.Ledger
  alias YagyeCore.Outbox
  alias YagyeCore.PaymentLinks.Schemas.PaymentLink
  alias YagyeCore.Payments.Schemas.{Payment, PaymentAttempt, PaymentEvent}
  alias YagyeCore.Repo

  # ── Public API ───────────────────────────────────────────────────────────────

  @doc """
  Creates an escrow hold for a payment that succeeded via an escrow-enabled payment link.
  Transitions the payment to escrow_held and posts the ledger entry.
  Called inside handle_provider_response/3 (within the Multi transaction context).
  """
  def create_hold(%Payment{} = payment, %PaymentAttempt{} = attempt, %PaymentLink{} = link) do
    now = DateTime.utc_now()
    auto_release_at = DateTime.add(now, link.escrow_auto_release_days * 86_400, :second)
    dispute_window_ends_at = DateTime.add(now, link.escrow_dispute_window_hours * 3600, :second)

    Multi.new()
    |> Multi.insert(:hold, fn _ ->
      EscrowHold.changeset(%EscrowHold{}, %{
        payment_id: payment.id,
        payment_link_id: link.id,
        merchant_id: payment.merchant_id,
        amount: payment.amount,
        currency: payment.currency,
        mode: payment.mode,
        auto_release_at: auto_release_at,
        dispute_window_ends_at: dispute_window_ends_at
      })
    end)
    |> Multi.run(:ledger, fn _repo, %{hold: hold} ->
      Ledger.post_escrow_hold(payment, attempt, hold.id)
    end)
    |> Multi.run(:transition, fn _repo, _ ->
      payment
      |> Payment.transition_changeset("escrow_held")
      |> Repo.update()
    end)
    |> Multi.run(:event, fn _repo, %{hold: hold} ->
      insert_event(payment, hold, "escrow.held")
    end)
    |> Multi.insert(:outbox, fn %{hold: hold} ->
      Outbox.build_changeset(
        hold,
        "escrow.held",
        %{
          public_id: hold.public_id,
          payment_public_id: payment.public_id,
          merchant_id: payment.merchant_id,
          amount: payment.amount,
          currency: payment.currency,
          auto_release_at: DateTime.to_iso8601(auto_release_at),
          dispute_window_ends_at: DateTime.to_iso8601(dispute_window_ends_at)
        },
        correlation_id: payment.public_id
      )
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{hold: hold}} -> {:ok, hold}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  @doc """
  Buyer confirms receipt — releases escrow to the merchant.
  Transitions hold to released, payment to escrow_released, posts ledger entries.
  """
  def confirm_release(hold_public_id, %PaymentAttempt{} = attempt) do
    with {:ok, hold} <- get_hold_for_update(hold_public_id, "held") do
      payment = Repo.get!(Payment, hold.payment_id)

      Multi.new()
      |> Multi.update(:hold, fn _ ->
        hold
        |> EscrowHold.transition_changeset("released")
        |> Ecto.Changeset.put_change(:buyer_confirmed_at, DateTime.utc_now())
        |> Ecto.Changeset.put_change(:released_at, DateTime.utc_now())
      end)
      |> Multi.run(:transition, fn _repo, _ ->
        payment
        |> Payment.transition_changeset("escrow_released")
        |> Repo.update()
      end)
      |> Multi.run(:escrow_ledger, fn _repo, %{hold: h} ->
        Ledger.post_escrow_release(payment, h.id)
      end)
      |> Multi.run(:settle_ledger, fn _repo, _ ->
        Ledger.post_payment_settled(payment, attempt)
      end)
      |> Multi.run(:event, fn _repo, %{hold: h} ->
        insert_event(payment, h, "escrow.released")
      end)
      |> Multi.insert(:outbox, fn %{hold: h} ->
        Outbox.build_changeset(
          h,
          "escrow.released",
          %{
            public_id: h.public_id,
            payment_public_id: payment.public_id,
            merchant_id: payment.merchant_id,
            released_at: DateTime.to_iso8601(DateTime.utc_now())
          },
          correlation_id: payment.public_id
        )
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{hold: h}} -> {:ok, h}
        {:error, _step, reason, _changes} -> {:error, reason}
      end
    end
  end

  @doc """
  Auto-releases an escrow hold when the auto_release timer fires.
  """
  def auto_release(hold_id, %PaymentAttempt{} = attempt) do
    hold = Repo.get!(EscrowHold, hold_id)

    if hold.state != "held" do
      {:error, :not_held}
    else
      payment = Repo.get!(Payment, hold.payment_id)

      Multi.new()
      |> Multi.update(:hold, fn _ ->
        hold
        |> EscrowHold.transition_changeset("released")
        |> Ecto.Changeset.put_change(:released_at, DateTime.utc_now())
      end)
      |> Multi.run(:transition, fn _repo, _ ->
        payment
        |> Payment.transition_changeset("escrow_released")
        |> Repo.update()
      end)
      |> Multi.run(:escrow_ledger, fn _repo, %{hold: h} ->
        Ledger.post_escrow_release(payment, h.id)
      end)
      |> Multi.run(:settle_ledger, fn _repo, _ ->
        Ledger.post_payment_settled(payment, attempt)
      end)
      |> Multi.run(:event, fn _repo, %{hold: h} ->
        insert_event(payment, h, "escrow.auto_released")
      end)
      |> Multi.insert(:outbox, fn %{hold: h} ->
        Outbox.build_changeset(
          h,
          "escrow.auto_released",
          %{
            public_id: h.public_id,
            payment_public_id: payment.public_id,
            merchant_id: payment.merchant_id,
            released_at: DateTime.to_iso8601(DateTime.utc_now())
          },
          correlation_id: payment.public_id
        )
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{hold: h}} -> {:ok, h}
        {:error, _step, reason, _changes} -> {:error, reason}
      end
    end
  end

  @doc """
  Buyer opens a dispute against the escrow hold.
  Transitions hold to disputed, payment to escrow_disputed.
  """
  def open_dispute(hold_public_id, actor, note) do
    with {:ok, hold} <- get_hold_for_update(hold_public_id, "held") do
      payment = Repo.get!(Payment, hold.payment_id)

      Multi.new()
      |> Multi.update(:hold, EscrowHold.transition_changeset(hold, "disputed"))
      |> Multi.run(:transition, fn _repo, _ ->
        payment
        |> Payment.transition_changeset("escrow_disputed")
        |> Repo.update()
      end)
      |> Multi.insert(:dispute_event, fn _ ->
        EscrowDisputeEvent.changeset(%EscrowDisputeEvent{}, %{
          escrow_hold_id: hold.id,
          merchant_id: hold.merchant_id,
          event_type: "dispute_opened",
          actor: actor,
          note: note
        })
      end)
      |> Multi.run(:event, fn _repo, %{hold: h} ->
        insert_event(payment, h, "escrow.disputed")
      end)
      |> Multi.insert(:outbox, fn %{hold: h} ->
        Outbox.build_changeset(
          h,
          "escrow.disputed",
          %{
            public_id: h.public_id,
            payment_public_id: payment.public_id,
            merchant_id: payment.merchant_id,
            actor: actor
          },
          correlation_id: payment.public_id
        )
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{hold: h}} -> {:ok, h}
        {:error, _step, reason, _changes} -> {:error, reason}
      end
    end
  end

  @doc """
  Ops resolves a disputed escrow.
  outcome: "release" (merchant wins) | "refund" (buyer wins)
  """
  def resolve_dispute(hold_public_id, outcome, actor, note, %PaymentAttempt{} = attempt) do
    with {:ok, hold} <- get_hold_for_update(hold_public_id, "disputed"),
         {:ok, outcome_atom} <- validate_outcome(outcome) do
      payment = Repo.get!(Payment, hold.payment_id)
      new_hold_state = if outcome_atom == :release, do: "released", else: "refunded"

      new_payment_state =
        if outcome_atom == :release, do: "escrow_released", else: "escrow_disputed"

      dispute_event_type =
        if outcome_atom == :release, do: "resolved_for_merchant", else: "resolved_for_buyer"

      ts_field = if outcome_atom == :release, do: :released_at, else: :refunded_at

      Multi.new()
      |> Multi.update(:hold, fn _ ->
        hold
        |> EscrowHold.transition_changeset(new_hold_state)
        |> Ecto.Changeset.put_change(ts_field, DateTime.utc_now())
      end)
      |> Multi.run(:transition, fn _repo, _ ->
        payment
        |> Payment.transition_changeset(new_payment_state)
        |> Repo.update()
      end)
      |> Multi.run(:ledger, fn _repo, %{hold: h} ->
        post_resolution_ledger(outcome_atom, payment, attempt, h.id)
      end)
      |> Multi.insert(:dispute_event, fn _ ->
        EscrowDisputeEvent.changeset(%EscrowDisputeEvent{}, %{
          escrow_hold_id: hold.id,
          merchant_id: hold.merchant_id,
          event_type: dispute_event_type,
          actor: actor,
          note: note
        })
      end)
      |> Multi.run(:event, fn _repo, %{hold: h} ->
        insert_event(payment, h, "escrow.#{dispute_event_type}")
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{hold: h}} -> {:ok, h}
        {:error, _step, reason, _changes} -> {:error, reason}
      end
    end
  end

  @doc """
  Fetches an escrow hold by public_id.
  """
  def get_hold(public_id) do
    case Repo.get_by(EscrowHold, public_id: public_id) do
      nil -> {:error, :not_found}
      hold -> {:ok, hold}
    end
  end

  @doc """
  Lists escrow holds for a merchant, optionally filtered by state.
  """
  def list_holds(merchant_id, opts \\ []) do
    state = Keyword.get(opts, :state)

    EscrowHold
    |> where([h], h.merchant_id == ^merchant_id)
    |> maybe_filter_state(state)
    |> order_by([h], desc: h.inserted_at)
    |> Repo.all()
  end

  @doc """
  Checks whether the given payment was made through an escrow-enabled payment link.
  Returns {:ok, %{enabled: true, payment_link: link}} | {:ok, %{enabled: false, payment_link: nil}}
  """
  def escrow_info_for(payment) do
    with session_id when is_binary(session_id) <-
           get_in(payment.metadata, ["checkout_session_id"]),
         %CheckoutSession{payment_link_id: link_id} when is_binary(link_id) <-
           Repo.get_by(CheckoutSession, public_id: session_id),
         %PaymentLink{escrow_enabled: true} = link <- Repo.get(PaymentLink, link_id) do
      {:ok, %{enabled: true, payment_link: link}}
    else
      _ -> {:ok, %{enabled: false, payment_link: nil}}
    end
  end

  # ── Private ──────────────────────────────────────────────────────────────────

  defp get_hold_for_update(public_id, expected_state) do
    case Repo.get_by(EscrowHold, public_id: public_id) do
      nil -> {:error, :not_found}
      %EscrowHold{state: ^expected_state} = hold -> {:ok, hold}
      %EscrowHold{} -> {:error, :invalid_state}
    end
  end

  defp maybe_filter_state(query, nil), do: query
  defp maybe_filter_state(query, state), do: where(query, [h], h.state == ^state)

  defp validate_outcome("release"), do: {:ok, :release}
  defp validate_outcome("refund"), do: {:ok, :refund}
  defp validate_outcome(_), do: {:error, :invalid_outcome}

  defp post_resolution_ledger(:release, payment, attempt, hold_id) do
    with {:ok, _} <- Ledger.post_escrow_release(payment, hold_id),
         {:ok, _} <- Ledger.post_payment_settled(payment, attempt) do
      {:ok, :released}
    end
  end

  defp post_resolution_ledger(:refund, payment, attempt, hold_id) do
    Ledger.post_escrow_refund(payment, attempt, hold_id)
  end

  defp insert_event(%Payment{} = payment, %EscrowHold{} = hold, event_type) do
    now = DateTime.utc_now()

    %PaymentEvent{}
    |> PaymentEvent.changeset(%{
      payment_id: payment.id,
      version: payment.version,
      event_type: event_type,
      from_state: hold.state,
      to_state: hold.state,
      actor: "system",
      correlation_id: payment.public_id,
      occurred_at: now,
      recorded_at: now
    })
    |> Repo.insert()
  end
end
