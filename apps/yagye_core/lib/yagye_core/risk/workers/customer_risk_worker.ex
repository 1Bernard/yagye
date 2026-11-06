defmodule YagyeCore.Risk.Workers.CustomerRiskWorker do
  @moduledoc false

  # Runs every 5 minutes via Oban cron.
  # Computes a 24-hour sliding window of transaction velocity, amount totals,
  # and failure counts per customer MSISDN hash, then writes to Redis.
  #
  # Key: yagye:features:customer:{msisdn_hash}  TTL: 1800s (30 min)
  #
  # The MSISDN hash comes from payments.metadata["msisdn_hash"] — written by
  # the outbox event serialiser and available on the payment row itself via
  # get_in(payment.metadata, ["msisdn_hash"]).

  use Oban.Worker, queue: :risk, max_attempts: 3

  require Logger

  import Ecto.Query

  alias YagyeCore.Payments.Schemas.Payment
  alias YagyeCore.Repo

  @window_hours 24
  @redis_ttl 1_800
  @redis_prefix "yagye:features:customer"

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    since = DateTime.add(DateTime.utc_now(), -@window_hours * 3600, :second)

    payments =
      Repo.all(
        from(p in Payment,
          where: p.inserted_at >= ^since,
          where: not is_nil(fragment("?->>'msisdn_hash'", p.metadata)),
          select: %{
            msisdn_hash: fragment("?->>'msisdn_hash'", p.metadata),
            amount: p.amount,
            state: p.state,
            merchant_id: p.merchant_id,
            risk_decision: p.risk_decision,
            inserted_at: p.inserted_at
          }
        )
      )

    payments
    |> Enum.group_by(& &1.msisdn_hash)
    |> Enum.each(fn {msisdn_hash, rows} ->
      features = compute_features(rows)
      write_to_redis(msisdn_hash, features)
    end)

    :ok
  end

  # ── Private ──────────────────────────────────────────────────────────────────

  defp compute_features(rows) do
    total = length(rows)
    succeeded = Enum.count(rows, &(&1.state == "succeeded"))
    failed = Enum.count(rows, &(&1.state == "failed"))
    amount_total = Enum.reduce(rows, 0, &(&1.amount + &2))
    merchant_count = rows |> Enum.map(& &1.merchant_id) |> Enum.uniq() |> length()
    flagged_count = Enum.count(rows, &(&1.risk_decision == "block"))

    amounts = rows |> Enum.map(& &1.amount) |> Enum.sort()

    since_1h = DateTime.add(DateTime.utc_now(), -3600, :second)
    rows_1h = Enum.filter(rows, &(DateTime.compare(to_utc(&1.inserted_at), since_1h) != :lt))

    %{
      txn_count_24h: total,
      txn_succeeded_24h: succeeded,
      txn_failed_24h: failed,
      txn_amount_24h_minor: amount_total,
      max_single_txn_minor: List.last(amounts) || 0,
      distinct_merchant_count: merchant_count,
      risk_block_count_24h: flagged_count,
      failure_rate: if(total > 0, do: Float.round(failed / total, 4), else: 0.0),
      # Field names read by apps/yagye_scoring/src/yagye_scoring/features/customer_risk.py
      attempt_count_1h: length(rows_1h),
      fail_count_1h: Enum.count(rows_1h, &(&1.state == "failed")),
      distinct_merchants_1h: rows_1h |> Enum.map(& &1.merchant_id) |> Enum.uniq() |> length(),
      amount_total_1h: Enum.reduce(rows_1h, 0, &(&1.amount + &2)),
      updated_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp to_utc(%DateTime{} = dt), do: dt
  defp to_utc(%NaiveDateTime{} = ndt), do: DateTime.from_naive!(ndt, "Etc/UTC")

  defp write_to_redis(msisdn_hash, features) do
    key = "#{@redis_prefix}:#{msisdn_hash}"

    case Jason.encode(features) do
      {:ok, json} ->
        case Redix.command(:yagye_redix, ["SETEX", key, to_string(@redis_ttl), json]) do
          {:ok, _} ->
            :ok

          {:error, reason} ->
            Logger.error("risk.customer_risk.redis_error", reason: inspect(reason))
        end

      {:error, reason} ->
        Logger.error("risk.customer_risk.encode_error", reason: inspect(reason))
    end
  end
end
