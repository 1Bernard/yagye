defmodule YagyeCore.Payouts.Workers.PayoutSagaWorker do
  @moduledoc false

  use Oban.Worker, queue: :payouts, max_attempts: 5

  import Ecto.Query

  require Logger

  alias YagyeCore.Ledger
  alias YagyeCore.Ledger.Schemas.Balance
  alias YagyeCore.Payments.Adapters.{MTNMomoAdapter, PaystackAdapter, SimulatorAdapter}
  alias YagyeCore.Payouts
  alias YagyeCore.Payouts.Schemas.{Payout, PayoutDestination}
  alias YagyeCore.Providers
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

        case Payouts.transition(payout, "submitted", %{
               submitted_at: now,
               saga_state: %{committed_at: DateTime.to_iso8601(now)}
             }) do
          {:ok, submitted} -> advance(submitted)
          err -> err
        end

      {:error, reason} ->
        Payouts.mark_failed(payout, "ledger_commit_failed:#{inspect(reason)}")
        :ok
    end
  end

  # Already dispatched — provider_reference is set; wait for webhook.
  defp advance(%Payout{state: "submitted", provider_reference: ref}) when is_binary(ref), do: :ok

  # Submitted but not yet dispatched — attempt provider submission now.
  defp advance(%Payout{state: "submitted"} = payout) do
    case dispatch_payout(payout) do
      {:ok, ref} ->
        Payouts.mark_paid(payout, ref)
        :ok

      {:pending, ref} ->
        Payouts.transition(payout, "submitted", %{provider_reference: ref})
        :ok

      {:error, reason} ->
        Logger.error("[PayoutSagaWorker] dispatch failed for payout #{payout.id}",
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end

  # Terminal states — nothing to do
  defp advance(%Payout{state: state})
       when state in ~w[paid returned failed cancelled],
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

  # ── Disbursement routing ──────────────────────────────────────────────────────

  # Simulation: route through the real simulator so disbursements are recorded
  # in the simulator DB (visible in admin UI) with genuine DISB_... references.
  defp dispatch_payout(%Payout{mode: "simulation"} = payout) do
    destination = Repo.get!(PayoutDestination, payout.destination_id)

    case PayoutDestination.decrypt_details(destination) do
      {:ok, details} ->
        with {:ok, credential} <- Providers.fetch_credential_for_psp("simulator", "simulation") do
          SimulatorAdapter.disburse(
            build_sim_disburse_params(payout, destination.kind, details),
            credential
          )
          |> normalize_disburse_result()
        end

      {:error, reason} ->
        {:error, {:decrypt_failed, reason}}
    end
  end

  defp dispatch_payout(%Payout{} = payout) do
    destination = Repo.get!(PayoutDestination, payout.destination_id)

    case PayoutDestination.decrypt_details(destination) do
      {:ok, details} -> route_payout_dispatch(payout, destination.kind, details)
      {:error, reason} -> {:error, {:decrypt_failed, reason}}
    end
  end

  defp build_sim_disburse_params(payout, "mobile_money", details) do
    %{
      amount: payout.amount,
      currency: payout.currency,
      reference: payout.id,
      destination_type: "mobile_money",
      recipient_msisdn: details["msisdn"] || details["phone_number"]
    }
  end

  defp build_sim_disburse_params(payout, kind, details) do
    %{
      amount: payout.amount,
      currency: payout.currency,
      reference: payout.id,
      destination_type: kind,
      recipient_msisdn: details["account_number"] || details["msisdn"]
    }
  end

  defp route_payout_dispatch(payout, "mobile_money", details) do
    msisdn = details["msisdn"] || details["phone_number"]

    with {:ok, credential} <- Providers.fetch_credential_for_psp("mtn_momo_gh", payout.mode) do
      MTNMomoAdapter.disburse(
        %{
          amount: payout.amount,
          currency: payout.currency,
          reference: payout.id,
          recipient_msisdn: msisdn
        },
        credential
      )
      |> normalize_disburse_result()
    end
  end

  defp route_payout_dispatch(payout, "bank", details) do
    with {:ok, credential} <- Providers.fetch_credential_for_psp("paystack", payout.mode) do
      PaystackAdapter.disburse(
        %{
          amount: payout.amount,
          currency: payout.currency,
          reference: payout.id,
          recipient_bank_code: details["bank_code"],
          recipient_account_number: details["account_number"],
          recipient_name: details["account_name"] || ""
        },
        credential
      )
      |> normalize_disburse_result()
    end
  end

  defp route_payout_dispatch(_payout, kind, _details) do
    {:error, {:unsupported_destination_kind, kind}}
  end

  defp normalize_disburse_result({:ok, %{provider_reference: ref}}), do: {:ok, ref}
  defp normalize_disburse_result({:pending, %{provider_reference: ref}}), do: {:pending, ref}
  defp normalize_disburse_result({:error, _} = err), do: err
end
