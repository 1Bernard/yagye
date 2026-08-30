defmodule YagyeCore.Payouts do
  @moduledoc false

  import Ecto.Query

  alias Ecto.Multi
  alias YagyeCore.Payouts.Schemas.{Payout, PayoutDestination}
  alias YagyeCore.Payouts.Workers.PayoutSagaWorker
  alias YagyeCore.Repo
  alias YagyeCore.Shared.Pagination

  # ── Public API ───────────────────────────────────────────────────────────────

  def create_payout(merchant_id, attrs) do
    attrs = Map.put(attrs, :merchant_id, merchant_id)

    Multi.new()
    |> Multi.insert(:payout, Payout.create_changeset(%Payout{}, attrs))
    |> Multi.run(:job, fn _repo, %{payout: payout} ->
      PayoutSagaWorker.new(%{payout_id: payout.id}) |> Oban.insert()
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{payout: payout}} -> {:ok, payout}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  def get_payout(id) do
    case Repo.get(Payout, id) do
      nil -> {:error, :not_found}
      payout -> {:ok, payout}
    end
  end

  def get_payout_by_public_id(public_id) do
    case Repo.get_by(Payout, public_id: public_id) do
      nil -> {:error, :not_found}
      payout -> {:ok, payout}
    end
  end

  def list_payouts(merchant_id, opts \\ []) do
    state = Keyword.get(opts, :state)
    base = from(p in Payout, where: p.merchant_id == ^merchant_id)
    base = if state, do: where(base, [p], p.state == ^state), else: base
    {:ok, Pagination.paginate(base, :public_id, opts)}
  end

  def transition(payout, to_state, extra \\ %{}) do
    payout
    |> Payout.transition_changeset(to_state, extra)
    |> Repo.update()
  end

  def mark_paid(payout, provider_reference) do
    transition(payout, "paid", %{
      provider_reference: provider_reference,
      completed_at: DateTime.utc_now()
    })
  end

  def mark_returned(payout, failure_code) do
    transition(payout, "returned", %{
      failure_code: failure_code,
      returned_at: DateTime.utc_now()
    })
  end

  def mark_failed(payout, failure_code) do
    transition(payout, "failed", %{failure_code: failure_code})
  end

  # ── Destinations ─────────────────────────────────────────────────────────────

  def create_destination(merchant_id, attrs) do
    %PayoutDestination{}
    |> PayoutDestination.create_changeset(Map.put(attrs, :merchant_id, merchant_id))
    |> Repo.insert()
  end

  def deactivate_destination(%PayoutDestination{} = dest) do
    dest
    |> PayoutDestination.deactivate_changeset()
    |> Repo.update()
  end

  @doc """
  Marks a payout destination as verified, enforcing SoD (verified_by must differ from added_by).
  Returns {:ok, destination} or {:error, changeset}.
  """
  def verify_destination(%PayoutDestination{} = dest, verified_by) do
    dest
    |> PayoutDestination.verify_changeset(verified_by)
    |> Repo.update()
  end

  @doc """
  Approves a manual payout, enforcing SoD (approved_by must differ from requested_by).
  Returns {:ok, payout} or {:error, changeset}.
  """
  def approve_payout(%Payout{} = payout, approved_by) do
    payout
    |> Payout.approve_changeset(approved_by)
    |> Repo.update()
  end

  def get_destination(id) do
    case Repo.get(PayoutDestination, id) do
      nil -> {:error, :not_found}
      dest -> {:ok, dest}
    end
  end

  def list_destinations(merchant_id) do
    from(d in PayoutDestination,
      where: d.merchant_id == ^merchant_id and d.active == true,
      order_by: [desc: :is_default, asc: :inserted_at]
    )
    |> Repo.all()
  end
end
