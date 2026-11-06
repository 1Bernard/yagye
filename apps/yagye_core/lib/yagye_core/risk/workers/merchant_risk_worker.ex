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

    # Merchant.status is "registered" | "approved"; liveness is tracked by activity_state.
    merchants =
      Repo.all(
        from(m in Merchant,
          where: m.activity_state == "active",
          select: {m.id, m.inserted_at}
        )
      )

    Enum.each(merchants, fn {merchant_id, merchant_inserted_at} ->
      features =
        merchant_id
        |> compute_features(since)
        |> Map.merge(scoring_contract_features(merchant_id, merchant_inserted_at))

      write_to_redis(merchant_id, features)
    end)

    :ok
  end

  # ── Private ──────────────────────────────────────────────────────────────────

  # Field names read by apps/yagye_scoring/src/yagye_scoring/features/merchant_risk.py.
  # Amounts are minor units except monthly_volume_ghs (major units, cedis).
  defp scoring_contract_features(merchant_id, merchant_inserted_at) do
    now = DateTime.utc_now()
    since_180d = DateTime.add(now, -180 * 86_400, :second)

    rows =
      Repo.all(
        from(p in Payment,
          where: p.merchant_id == ^merchant_id,
          where: p.inserted_at >= ^since_180d,
          select: %{state: p.state, amount: p.amount, inserted_at: p.inserted_at}
        )
      )

    in_window = fn days ->
      cutoff = DateTime.add(now, -days * 86_400, :second)
      Enum.filter(rows, &(DateTime.compare(&1.inserted_at, cutoff) != :lt))
    end

    rate = fn subset, state ->
      case length(subset) do
        0 -> 0.0
        n -> Float.round(Enum.count(subset, &(&1.state == state)) / n, 4)
      end
    end

    rows_30d = in_window.(30)
    rows_90d = in_window.(90)
    succeeded_30d = Enum.filter(rows_30d, &(&1.state == "succeeded"))
    amounts = Enum.map(rows_90d, & &1.amount)

    %{
      monthly_volume_ghs: Enum.reduce(succeeded_30d, 0, &(&1.amount + &2)) / 100,
      chargeback_rate_30d: rate.(rows_30d, "chargebacked"),
      chargeback_rate_90d: rate.(rows_90d, "chargebacked"),
      chargeback_rate_180d: rate.(rows, "chargebacked"),
      dispute_rate_90d: rate.(rows_90d, "disputed"),
      avg_payment_amount: mean(amounts),
      payment_amount_std: std(amounts),
      merchant_age_days:
        if(merchant_inserted_at,
          do: DateTime.diff(now, merchant_inserted_at, :second) |> div(86_400),
          else: 0
        )
    }
  end

  defp mean([]), do: 0.0
  defp mean(xs), do: Float.round(Enum.sum(xs) / length(xs), 2)

  defp std(xs) when length(xs) < 2, do: 0.0

  defp std(xs) do
    m = Enum.sum(xs) / length(xs)
    var = Enum.reduce(xs, 0.0, fn x, acc -> acc + (x - m) * (x - m) end) / (length(xs) - 1)
    Float.round(:math.sqrt(var), 2)
  end

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
