defmodule YagyeCore.Risk.Workers.MerchantRiskWorker do
  @moduledoc false

  # Runs every 5 minutes via Oban cron.
  # Computes 7-day rolling risk signals per merchant:
  # chargeback rate, dispute rate, failed payment rate, risk block rate.
  #
  # Key: yagye:features:merchant:{merchant_id}  TTL: 1800s (30 min)

  use Oban.Worker, queue: :risk, max_attempts: 3

  require Logger

  import Ecto.Query

  alias YagyeCore.Merchants.Schemas.Merchant
  alias YagyeCore.Payments.Schemas.Payment
  alias YagyeCore.Repo

  @window_days 7
  @redis_ttl 1_800
  @redis_prefix "yagye:features:merchant"

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    since = DateTime.add(DateTime.utc_now(), -@window_days * 86_400, :second)

    merchant_ids = Repo.all(from(m in Merchant, where: m.status == "active", select: m.id))

    Enum.each(merchant_ids, fn merchant_id ->
      features = compute_features(merchant_id, since)
      write_to_redis(merchant_id, features)
    end)

    :ok
  end

  # ── Private ──────────────────────────────────────────────────────────────────

  defp compute_features(merchant_id, since) do
    rows =
      Repo.all(
        from(p in Payment,
          where: p.merchant_id == ^merchant_id,
          where: p.inserted_at >= ^since,
          select: %{
            state: p.state,
            amount: p.amount,
            risk_decision: p.risk_decision
          }
        )
      )

    total = length(rows)
    succeeded = Enum.count(rows, &(&1.state == "succeeded"))
    failed = Enum.count(rows, &(&1.state == "failed"))
    chargebacked = Enum.count(rows, &(&1.state == "chargebacked"))
    disputed = Enum.count(rows, &(&1.state == "disputed"))
    risk_blocked = Enum.count(rows, &(&1.risk_decision == "block"))
    risk_reviewed = Enum.count(rows, &(&1.risk_decision == "review"))
    volume = Enum.reduce(rows, 0, &(&1.amount + &2))

    %{
      txn_count_7d: total,
      txn_succeeded_7d: succeeded,
      txn_volume_7d_minor: volume,
      chargeback_rate: if(total > 0, do: Float.round(chargebacked / total, 4), else: 0.0),
      dispute_rate: if(total > 0, do: Float.round(disputed / total, 4), else: 0.0),
      failure_rate: if(total > 0, do: Float.round(failed / total, 4), else: 0.0),
      risk_block_rate: if(total > 0, do: Float.round(risk_blocked / total, 4), else: 0.0),
      risk_review_rate: if(total > 0, do: Float.round(risk_reviewed / total, 4), else: 0.0),
      updated_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp write_to_redis(merchant_id, features) do
    key = "#{@redis_prefix}:#{merchant_id}"

    case Jason.encode(features) do
      {:ok, json} ->
        case Redix.command(:yagye_redix, ["SETEX", key, to_string(@redis_ttl), json]) do
          {:ok, _} ->
            :ok

          {:error, reason} ->
            Logger.error("risk.merchant_risk.redis_error", reason: inspect(reason))
        end

      {:error, reason} ->
        Logger.error("risk.merchant_risk.encode_error", reason: inspect(reason))
    end
  end
end
