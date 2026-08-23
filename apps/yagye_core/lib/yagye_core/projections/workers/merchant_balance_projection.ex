defmodule YagyeCore.Projections.Workers.MerchantBalanceProjection do
  @moduledoc false

  # Updates proj_merchant_balances from payment outcome events.
  #
  # Dedup on event_id: if last_event_id == envelope.event_id the row was already
  # updated by this exact event — skip. This is what makes counter increments safe
  # to retry. Version fencing does NOT work for counters (a fence only prevents
  # older events from overwriting newer state; it cannot prevent double-counting).

  use Oban.Worker, queue: :projections, max_attempts: 5

  import Ecto.Query

  alias YagyeCore.Outbox.EventEnvelope
  alias YagyeCore.Projections.Schemas.MerchantBalance
  alias YagyeCore.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"envelope" => raw_envelope}}) do
    envelope = EventEnvelope.from_map(raw_envelope)
    apply_event(envelope)
  end

  # ── Event handlers ────────────────────────────────────────────────────────────

  defp apply_event(%EventEnvelope{event_type: "payment.succeeded"} = env) do
    amount = env.payload["amount"] || 0
    net = env.payload["net_amount"] || amount
    currency = env.payload["currency"]

    upsert_balance(env, currency, fn q ->
      from(b in q,
        update: [
          inc: [available: ^net, lifetime_volume: ^amount],
          set: [last_event_id: ^env.event_id, last_applied_at: ^env.occurred_at]
        ]
      )
    end)
  end

  defp apply_event(%EventEnvelope{event_type: "payment.failed"} = env) do
    currency = env.payload["currency"]

    upsert_balance(env, currency, fn q ->
      from(b in q,
        update: [
          set: [last_event_id: ^env.event_id, last_applied_at: ^env.occurred_at]
        ]
      )
    end)
  end

  defp apply_event(%EventEnvelope{event_type: "payment.refunded"} = env) do
    amount = env.payload["refund_amount"] || 0
    currency = env.payload["currency"]

    upsert_balance(env, currency, fn q ->
      from(b in q,
        update: [
          inc: [available: ^(-amount)],
          set: [last_event_id: ^env.event_id, last_applied_at: ^env.occurred_at]
        ]
      )
    end)
  end

  defp apply_event(_env), do: :ok

  # ── Helpers ───────────────────────────────────────────────────────────────────

  defp upsert_balance(env, currency, update_fn) do
    key = {env.merchant_id, currency, env.mode}

    Repo.transaction(fn ->
      balance = get_or_create_balance(env.merchant_id, currency, env.mode)

      if balance.last_event_id == env.event_id do
        # Already applied this event — idempotent skip
        :ok
      else
        MerchantBalance
        |> where_pk(key)
        |> update_fn.()
        |> Repo.update_all([])
      end
    end)

    :ok
  end

  defp get_or_create_balance(merchant_id, currency, mode) do
    case Repo.get_by(MerchantBalance, merchant_id: merchant_id, currency: currency, mode: mode) do
      nil ->
        %MerchantBalance{}
        |> MerchantBalance.changeset(%{
          merchant_id: merchant_id,
          currency: currency,
          mode: mode
        })
        |> Repo.insert!(on_conflict: :nothing)

        Repo.get_by!(MerchantBalance, merchant_id: merchant_id, currency: currency, mode: mode)

      balance ->
        balance
    end
  end

  defp where_pk(query, {merchant_id, currency, mode}) do
    from(b in query,
      where: b.merchant_id == ^merchant_id and b.currency == ^currency and b.mode == ^mode
    )
  end
end
