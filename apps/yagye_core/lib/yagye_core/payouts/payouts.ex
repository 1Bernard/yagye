defmodule YagyeCore.Payouts do
  @moduledoc false

  import Ecto.Query

  alias Ecto.Multi
  alias YagyeCore.Merchants.Schemas.Merchant
  alias YagyeCore.Outbox
  alias YagyeCore.Payouts.Schemas.{Payout, PayoutDestination}
  alias YagyeCore.Payouts.Workers.PayoutSagaWorker
  alias YagyeCore.Repo
  alias YagyeCore.Shared.Pagination

  # ── Public API ───────────────────────────────────────────────────────────────

  def create_payout(merchant_id, attrs) do
    destination_ref = attrs["destination_id"] || attrs[:destination_id]

    with {:ok, attrs} <- maybe_resolve_destination(attrs, destination_ref, merchant_id) do
      Multi.new()
      |> Multi.insert(:payout, Payout.create_changeset(%Payout{}, attrs))
      |> Multi.run(:job, fn _repo, %{payout: payout} ->
        PayoutSagaWorker.new(%{payout_id: payout.id}) |> Oban.insert()
      end)
      |> Multi.insert(:outbox, fn %{payout: payout} ->
        Outbox.build_changeset(
          payout,
          "payout.created",
          %{
            payout_code: payout.public_id,
            merchant_code: merchant_code(merchant_id),
            state: payout.state,
            amount: payout.amount,
            currency: payout.currency,
            destination_type: payout.destination_type,
            destination_fingerprint: payout.destination_fingerprint,
            scheduled_for: payout.scheduled_for && Date.to_iso8601(payout.scheduled_for),
            mode: payout.mode
          },
          correlation_id: payout.public_id
        )
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{payout: payout}} -> {:ok, payout}
        {:error, _step, reason, _changes} -> {:error, reason}
      end
    end
  end

  # Only resolve public_id refs from the API; internal UUID refs bypass (tests, saga).
  defp maybe_resolve_destination(attrs, ref, merchant_id)
       when is_binary(ref) and binary_part(ref, 0, 4) == "pdt_" do
    case Repo.get_by(PayoutDestination, public_id: ref, merchant_id: merchant_id, active: true) do
      nil ->
        {:error, :destination_not_found}

      dest ->
        {:ok,
         attrs
         |> Map.put(:merchant_id, merchant_id)
         |> Map.put(:destination_id, dest.id)
         |> Map.put(:destination_type, dest.kind)
         |> Map.put(:destination_fingerprint, dest.fingerprint)}
    end
  end

  defp maybe_resolve_destination(attrs, _ref, merchant_id) do
    {:ok, Map.put(attrs, :merchant_id, merchant_id)}
  end

  defp merchant_code(merchant_id) do
    case Repo.get(Merchant, merchant_id) do
      %Merchant{public_id: code} -> code
      nil -> nil
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

  @doc """
  Sets one destination as default, clearing is_default on all others for the same merchant.
  Returns {:ok, destination} or {:error, :not_found | changeset}.
  """
  def set_default_destination(merchant_id, destination_id) do
    Repo.transaction(fn ->
      dest =
        Repo.get_by(PayoutDestination, id: destination_id, merchant_id: merchant_id, active: true)

      if is_nil(dest) do
        Repo.rollback(:not_found)
      else
        from(d in PayoutDestination,
          where:
            d.merchant_id == ^merchant_id and d.id != ^destination_id and d.is_default == true
        )
        |> Repo.update_all(set: [is_default: false])

        dest
        |> Ecto.Changeset.change(is_default: true)
        |> Repo.update!()
      end
    end)
  end

  def get_destination_by_public_id(public_id) do
    case Repo.get_by(PayoutDestination, public_id: public_id, active: true) do
      nil -> {:error, :not_found}
      dest -> {:ok, dest}
    end
  end
end
