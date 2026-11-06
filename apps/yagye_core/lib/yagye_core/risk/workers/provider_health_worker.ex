defmodule YagyeCore.Risk.Workers.ProviderHealthWorker do
  @moduledoc false

  # Runs every 2 minutes via Oban cron.
  # Computes a 2-hour sliding window of success_rate, latency percentiles,
  # and error breakdown for every active provider, then writes to Redis so
  # the yagye_scoring service always has fresh features.
  #
  # Key: yagye:features:provider:{code}  TTL: 1800s (30 min)
  # Also callable as update_one/2 for synchronous post-payment refresh.

  use Oban.Worker, queue: :risk, max_attempts: 3

  require Logger

  import Ecto.Query

  alias YagyeCore.Payments.Schemas.PaymentAttempt
  alias YagyeCore.Providers.Schemas.Provider
  alias YagyeCore.Repo
  alias YagyeCore.Routing.CircuitBreaker

  @window_hours 2
  @redis_ttl 1_800
  @redis_prefix "yagye:features:provider"

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    providers = Repo.all(from(p in Provider, where: p.active == true, select: {p.id, p.code}))

    Enum.each(providers, fn {provider_id, provider_code} ->
      features = compute_features(provider_id)
      write_to_redis(provider_code, features)
    end)

    :ok
  end

  # Called synchronously after a payment outcome to avoid waiting for the next cron tick.
  def update_one(provider_id, provider_code) do
    features = compute_features(provider_id)
    write_to_redis(provider_code, features)
  end

  # ── Private ──────────────────────────────────────────────────────────────────

  defp compute_features(provider_id) do
    now = DateTime.utc_now()
    # Read 24h so we can also emit the 1h/24h fields consumed by
    # yagye_scoring.features.provider_health; legacy fields stay on the 2h window.
    since_24h = DateTime.add(now, -24 * 3600, :second)
    since = DateTime.add(now, -@window_hours * 3600, :second)
    since_1h = DateTime.add(now, -3600, :second)

    rows_24h =
      Repo.all(
        from(pa in PaymentAttempt,
          where: pa.provider_id == ^provider_id,
          where: pa.inserted_at >= ^since_24h,
          where: pa.state in ["succeeded", "failed", "timed_out"],
          select: %{
            state: pa.state,
            latency_ms: pa.latency_ms,
            error_class: pa.error_class,
            inserted_at: pa.inserted_at
          }
        )
      )

    rows = Enum.filter(rows_24h, &(DateTime.compare(&1.inserted_at, since) != :lt))
    rows_1h = Enum.filter(rows_24h, &(DateTime.compare(&1.inserted_at, since_1h) != :lt))

    provider_id
    |> legacy_features(rows)
    |> Map.merge(scoring_contract_features(provider_id, rows_1h, rows_24h))
  end

  # Field names read by apps/yagye_scoring/src/yagye_scoring/features/provider_health.py.
  defp scoring_contract_features(provider_id, rows_1h, rows_24h) do
    latencies_1h = rows_1h |> Enum.map(& &1.latency_ms) |> Enum.reject(&is_nil/1)

    %{
      success_rate_1h: success_rate(rows_1h, 0.85),
      success_rate_24h: success_rate(rows_24h, 0.85),
      avg_latency_ms_1h:
        if(latencies_1h == [],
          do: 2000.0,
          else: Float.round(Enum.sum(latencies_1h) / length(latencies_1h), 1)
        ),
      circuit_breaker_state: circuit_breaker_state(provider_id)
    }
  end

  defp success_rate([], default), do: default

  defp success_rate(rows, _default),
    do: Float.round(Enum.count(rows, &(&1.state == "succeeded")) / length(rows), 4)

  defp circuit_breaker_state(provider_id) do
    case CircuitBreaker.state(provider_id) do
      :open -> 2
      :half_open -> 1
      _ -> 0
    end
  rescue
    _ -> 0
  end

  defp legacy_features(_provider_id, rows) do
    total = length(rows)

    if total == 0 do
      %{
        success_rate: 0.85,
        p50_latency_ms: 2000,
        p95_latency_ms: 5000,
        total_count: 0,
        definite_failure_rate: 0.0,
        indeterminate_rate: 0.0,
        updated_at: DateTime.utc_now() |> DateTime.to_iso8601()
      }
    else
      succeeded = Enum.count(rows, &(&1.state == "succeeded"))
      definite_failures = Enum.count(rows, &(&1.error_class == "definite_failure"))
      indeterminate = Enum.count(rows, &(&1.error_class == "indeterminate"))

      latencies =
        rows
        |> Enum.map(& &1.latency_ms)
        |> Enum.reject(&is_nil/1)
        |> Enum.sort()

      %{
        success_rate: Float.round(succeeded / total, 4),
        p50_latency_ms: percentile(latencies, 0.5),
        p95_latency_ms: percentile(latencies, 0.95),
        total_count: total,
        definite_failure_rate: Float.round(definite_failures / total, 4),
        indeterminate_rate: Float.round(indeterminate / total, 4),
        updated_at: DateTime.utc_now() |> DateTime.to_iso8601()
      }
    end
  end

  defp percentile([], _), do: nil

  defp percentile(sorted, p) do
    idx = trunc((length(sorted) - 1) * p)
    Enum.at(sorted, idx)
  end

  defp write_to_redis(provider_code, features) do
    key = "#{@redis_prefix}:#{provider_code}"

    case Jason.encode(features) do
      {:ok, json} ->
        case Redix.command(:yagye_redix, ["SETEX", key, to_string(@redis_ttl), json]) do
          {:ok, _} ->
            Logger.debug("risk.provider_health.written", provider: provider_code)

          {:error, reason} ->
            Logger.error("risk.provider_health.redis_error",
              provider: provider_code,
              reason: inspect(reason)
            )
        end

      {:error, reason} ->
        Logger.error("risk.provider_health.encode_error",
          provider: provider_code,
          reason: inspect(reason)
        )
    end
  end
end
