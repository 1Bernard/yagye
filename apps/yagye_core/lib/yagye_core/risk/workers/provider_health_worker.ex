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
    since = DateTime.add(DateTime.utc_now(), -@window_hours * 3600, :second)

    rows =
      Repo.all(
        from(pa in PaymentAttempt,
          where: pa.provider_id == ^provider_id,
          where: pa.inserted_at >= ^since,
          where: pa.state in ["succeeded", "failed", "timed_out"],
          select: %{
            state: pa.state,
            latency_ms: pa.latency_ms,
            error_class: pa.error_class
          }
        )
      )

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
