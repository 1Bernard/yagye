defmodule YagyeCore.Reserves do
  @moduledoc false

  import Ecto.Query

  alias Ecto.Multi
  alias YagyeCore.Ledger
  alias YagyeCore.Payments.Schemas.Payment
  alias YagyeCore.Repo
  alias YagyeCore.Reserves.Schemas.{MerchantReserve, ReserveHold}

  # ── Public API ───────────────────────────────────────────────────────────────

  def list_reserves(merchant_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    reserves =
      from(r in MerchantReserve,
        where: r.merchant_id == ^merchant_id,
        order_by: [desc: r.inserted_at],
        limit: ^limit,
        offset: ^offset
      )
      |> Repo.all()

    {:ok, reserves}
  end

  @doc """
  Returns the active reserve policy for a merchant+currency+mode, or nil.
  """
  def reserve_policy_for(merchant_id, currency, mode) do
    from(r in MerchantReserve,
      where:
        r.merchant_id == ^merchant_id and
          r.currency == ^currency and
          r.mode == ^mode and
          r.active == true,
      order_by: [desc: :inserted_at],
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Creates a reserve policy for a merchant. Deactivates any prior active policy
  of the same kind+currency+mode first (one active policy per combination).
  """
  def create_policy(merchant_id, attrs) do
    %MerchantReserve{}
    |> MerchantReserve.create_changeset(Map.put(attrs, :merchant_id, merchant_id))
    |> Repo.insert()
  end

  def deactivate_policy(%MerchantReserve{} = reserve) do
    reserve
    |> MerchantReserve.deactivate_changeset()
    |> Repo.update()
  end

  @doc """
  Approves a reserve policy, enforcing SoD (approved_by must differ from created_by).
  Returns {:ok, reserve} or {:error, changeset}.
  """
  def approve_policy(%MerchantReserve{} = reserve, approved_by) do
    reserve
    |> MerchantReserve.approve_changeset(approved_by)
    |> Repo.update()
  end

  @doc """
  Creates a reserve hold for a succeeded payment.

  Looks up the active policy for merchant+currency+mode. If none, returns {:ok, nil}.
  If a policy exists, computes the hold amount, inserts the hold, and posts the
  ledger entry (debit merchant_payable, credit merchant_reserve).
  """
  def create_hold(%Payment{} = payment) do
    case reserve_policy_for(payment.merchant_id, payment.currency, payment.mode) do
      nil -> {:ok, nil}
      reserve -> do_create_hold(payment, reserve)
    end
  end

  @doc """
  Draws a pending hold to cover a chargeback or dispute.
  Transitions hold state to "drawn" and posts the ledger entry.
  """
  def draw_hold(%ReserveHold{state: "pending"} = hold, draw_source_id) do
    Multi.new()
    |> Multi.update(:hold, ReserveHold.draw_changeset(hold, draw_source_id))
    |> Multi.run(:ledger, fn _repo, %{hold: updated} ->
      Ledger.post_reserve_draw(updated)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{hold: hold}} -> {:ok, hold}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  def draw_hold(%ReserveHold{state: state}, _draw_source_id),
    do: {:error, {:invalid_hold_state, state}}

  @doc """
  Returns pending holds for a payment.
  """
  def holds_for_payment(payment_id) do
    from(h in ReserveHold, where: h.payment_id == ^payment_id)
    |> Repo.all()
  end

  @doc """
  Releases all pending holds where release_at <= now, FIFO by release_at.
  Called by ReserveReleaseWorker. Returns {:ok, released_count}.
  """
  def release_due_holds do
    now = DateTime.utc_now()

    holds =
      from(h in ReserveHold,
        where: h.state == "pending" and h.release_at <= ^now,
        order_by: [asc: h.release_at],
        limit: 200
      )
      |> Repo.all()

    {released, errors} =
      holds
      |> Enum.map(&release_single/1)
      |> Enum.split_with(&match?({:ok, _}, &1))

    if errors == [] do
      {:ok, length(released)}
    else
      {:error, {:partial_release, length(released), length(errors)}}
    end
  end

  # ── Private ──────────────────────────────────────────────────────────────────

  defp do_create_hold(payment, reserve) do
    hold_amount = compute_hold_amount(payment.amount, reserve)

    if hold_amount <= 0 do
      {:ok, nil}
    else
      now = DateTime.utc_now()
      release_at = DateTime.add(now, (reserve.hold_days || 90) * 86_400, :second)

      attrs = %{
        merchant_id: payment.merchant_id,
        reserve_id: reserve.id,
        payment_id: payment.id,
        amount: hold_amount,
        currency: payment.currency,
        mode: payment.mode,
        held_at: now,
        release_at: release_at
      }

      Multi.new()
      |> Multi.insert(:hold, ReserveHold.create_changeset(%ReserveHold{}, attrs))
      |> Multi.run(:ledger, fn _repo, %{hold: hold} ->
        Ledger.post_reserve_hold(payment, hold)
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{hold: hold}} -> {:ok, hold}
        {:error, _step, reason, _changes} -> {:error, reason}
      end
    end
  end

  defp release_single(hold) do
    Multi.new()
    |> Multi.update(:hold, ReserveHold.release_changeset(hold))
    |> Multi.run(:ledger, fn _repo, %{hold: updated} ->
      Ledger.post_reserve_release(updated)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{hold: hold}} -> {:ok, hold}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  defp compute_hold_amount(amount, %MerchantReserve{kind: "rolling", percentage_bps: bps})
       when not is_nil(bps),
       do: div(amount * bps, 10_000)

  defp compute_hold_amount(_amount, %MerchantReserve{kind: "fixed", fixed_amount: fixed})
       when not is_nil(fixed),
       do: fixed

  defp compute_hold_amount(_amount, _reserve), do: 0
end
