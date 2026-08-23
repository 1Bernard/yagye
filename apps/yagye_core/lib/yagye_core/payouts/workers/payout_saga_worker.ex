defmodule YagyeCore.Payouts.Workers.PayoutSagaWorker do
  @moduledoc false

  use Oban.Worker, queue: :payouts, max_attempts: 5

  import Ecto.Query

  alias YagyeCore.Ledger
  alias YagyeCore.Ledger.Schemas.Balance
  alias YagyeCore.Payouts
  alias YagyeCore.Payouts.Schemas.{Payout, PayoutDestination}
  alias YagyeCore.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"payout_id" => payout_id}}) do
    with {:ok, payout} <- load_payout(payout_id) do
      advance(payout)
    end
  end

  # ── State machine ─────────────────────────────────────────────────────────────

  defp advance(%Payout{state: "scheduled"} = payout) do
    destination = Repo.get!(PayoutDestination, payout.destination_id)

    cond do
      not destination.active ->
        Payouts.mark_failed(payout, "destination_inactive")
        :ok

      destination.verification_state != "verified" ->
        Payouts.mark_failed(payout, "destination_unverified")
        :ok

      true ->
        with {:ok, updated} <- Payouts.transition(payout, "validating") do
          advance(updated)
        end
    end
  end

  defp advance(%Payout{state: "validating"} = payout) do
    case check_merchant_balance(payout) do
      :ok ->
        with {:ok, updated} <- Payouts.transition(payout, "reserving") do
          advance(updated)
        end

      {:error, :insufficient_balance} ->
        Payouts.mark_failed(payout, "insufficient_payable_balance")
        :ok
    end
  end

  defp advance(%Payout{state: "reserving"} = payout) do
    case post_payout_committed(payout) do
      {:ok, _entry} ->
        now = DateTime.utc_now()

        Payouts.transition(payout, "submitted", %{
          submitted_at: now,
          saga_state: %{committed_at: DateTime.to_iso8601(now)}
        })

        # Provider submission deferred to P13; payout sits in "submitted"
        # until a webhook or polling job transitions it to paid/returned.
        :ok

      {:error, reason} ->
        Payouts.mark_failed(payout, "ledger_commit_failed:#{inspect(reason)}")
        :ok
    end
  end

  # Terminal states — nothing to do
  defp advance(%Payout{state: state})
       when state in ~w[submitted paid returned failed cancelled],
       do: :ok

  # ── Helpers ──────────────────────────────────────────────────────────────────

  defp load_payout(payout_id) do
    case Repo.get(Payout, payout_id) do
      nil -> {:error, :not_found}
      payout -> {:ok, payout}
    end
  end

  defp check_merchant_balance(payout) do
    account_code =
      "merchant_payable:#{payout.merchant_id}:#{payout.currency}:#{payout.mode}"

    balance =
      from(a in YagyeCore.Ledger.Schemas.Account,
        join: b in Balance,
        on: b.account_id == a.id,
        where: a.code == ^account_code,
        select: b.balance
      )
      |> Repo.one()
      |> then(&(&1 || 0))

    if balance >= payout.amount do
      :ok
    else
      {:error, :insufficient_balance}
    end
  end

  # Debit merchant_payable, credit payout_transit — funds committed for transfer
  defp post_payout_committed(payout) do
    Ledger.post_payout_committed(payout)
  end
end
