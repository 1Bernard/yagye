defmodule YagyeCore.Shared.RateLimiter do
  @moduledoc false

  # Fixed-window rate limiter backed by a node-local ETS table.
  #
  # IMPORTANT — node-local limitation: each node in a cluster holds its own
  # counter. In an N-node cluster the effective ceiling is limit × N before
  # any single node rejects. Acceptable for P1 (single node). Upgrade to a
  # Redis-backed counter when clustering (P3+).
  #
  # Window: 60 seconds (one bucket per minute per key).
  # Default limit: 1 000 req/min per key.
  # Stale buckets are purged once per minute by the GenServer.

  use GenServer

  @table :yagye_rate_limiter
  @window_seconds 60
  @default_limit 1_000

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  # Returns true when the request is allowed, false when the limit is exceeded.
  # key is typically the remote IP binary.
  def allow?(key, limit \\ @default_limit) do
    window = div(System.os_time(:second), @window_seconds)
    ets_key = {key, window}
    count = :ets.update_counter(@table, ets_key, {2, 1}, {ets_key, 0})
    count <= limit
  end

  # ── GenServer ────────────────────────────────────────────────────────────────

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
