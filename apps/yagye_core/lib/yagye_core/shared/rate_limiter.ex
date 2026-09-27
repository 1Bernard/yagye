defmodule YagyeCore.Shared.RateLimiter do
  @moduledoc false

  # Fixed-window rate limiter with two-tier storage:
  #
  #   Primary  — Redis INCR + EXPIRE. Accurate across every node in the cluster.
  #              Key format: "rl:{key}:{60-second bucket}" with 120 s TTL.
  #
  #   Fallback — Node-local ETS table used when Redis is unavailable.
  #              Carries the P1-era caveat: effective ceiling is limit × N nodes.
  #              Stale ETS buckets are purged every 60 seconds by this GenServer.
  #
  # Callers see allow?/2 — they never know which tier served the check.

  use GenServer

  require Logger

  @table :yagye_rate_limiter_ets
  @window_seconds 60
  @default_limit 1_000

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @spec allow?(String.t(), pos_integer()) :: boolean()
  def allow?(key, limit \\ @default_limit) do
    window = div(System.os_time(:second), @window_seconds)

    case redis_allow?(key, window, limit) do
      {:ok, result} ->
        result

      {:error, reason} ->
        Logger.warning("[RateLimiter] Redis unavailable, falling back to ETS",
          reason: inspect(reason)
        )

        ets_allow?(key, window, limit)
    end
  end

  # ── Redis path ───────────────────────────────────────────────────────────────

  defp redis_allow?(key, window, limit) do
    redis_key = "rl:#{key}:#{window}"

    case Redix.pipeline(:yagye_redix, [
           ["INCR", redis_key],
           ["EXPIRE", redis_key, @window_seconds * 2]
         ]) do
      {:ok, [count, _]} -> {:ok, count <= limit}
      {:error, _} = err -> err
    end
  end

  # ── ETS fallback path ────────────────────────────────────────────────────────

  defp ets_allow?(key, window, limit) do
    ets_key = {key, window}
    count = :ets.update_counter(@table, ets_key, {2, 1}, {ets_key, 0})
    count <= limit
  end

  # ── GenServer (ETS table + periodic cleanup) ─────────────────────────────────

  @impl GenServer
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])
    schedule_cleanup()
    {:ok, %{}}
  end

  @impl GenServer
  def handle_info(:cleanup, state) do
    current_window = div(System.os_time(:second), @window_seconds)

    :ets.select_delete(@table, [
      {{{:_, :"$1"}, :_}, [{:<, :"$1", current_window}], [true]}
    ])

    schedule_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, :timer.minutes(1))
  end
end
