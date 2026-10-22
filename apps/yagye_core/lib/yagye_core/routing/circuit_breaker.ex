defmodule YagyeCore.Routing.CircuitBreaker do
  @moduledoc false

  use GenServer

  require Logger

  # Open the circuit after this many consecutive failures.
  @failure_threshold 5
  # How long (ms) the circuit stays open before allowing a probe through.
  @recovery_period_ms 60_000
  @table :yagye_circuit_breaker

  # ── Public API ───────────────────────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Called after a provider responds successfully. Closes the circuit if it was half-open."
  def record_success(provider_id) do
    GenServer.cast(__MODULE__, {:success, provider_id})
  end

  @doc "Called after a definite or retryable failure. Opens the circuit after the threshold."
  def record_failure(provider_id) do
    GenServer.cast(__MODULE__, {:failure, provider_id})
  end

  @doc """
  Returns the current circuit state for a provider: `:closed`, `:open`, or `:half_open`.

  Reads directly from the ETS table — no GenServer round-trip — so it is safe to call
  on every payment dispatch without adding latency.
  """
  def state(provider_id) do
    case :ets.lookup(@table, provider_id) do
      [] ->
        :closed

      [{_id, :open, _count, opened_at}] ->
        if elapsed_ms(opened_at) >= @recovery_period_ms, do: :half_open, else: :open

      [{_id, current_state, _count, _opened_at}] ->
        current_state
    end
  end

  @doc """
  Returns provider IDs whose circuits are fully open (not yet in half-open recovery).

  These should be added to the excluded list in `Routing.evaluate/4`. Half-open providers
  are intentionally NOT excluded — the next payment to that provider acts as the probe that
  decides whether to close the circuit or re-open it.
  """
  def open_provider_ids do
    now = System.monotonic_time(:millisecond)

    :ets.tab2list(@table)
    |> Enum.filter(fn {_id, circuit_state, _count, opened_at} ->
      circuit_state == :open and not is_nil(opened_at) and
        now - opened_at < @recovery_period_ms
    end)
    |> Enum.map(fn {id, _state, _count, _opened_at} -> id end)
  end

  # ── GenServer callbacks ───────────────────────────────────────────────────────

  @impl GenServer
  def init(_opts) do
    :ets.new(@table, [:set, :named_table, :public, read_concurrency: true])
    {:ok, %{}}
  end

  @impl GenServer
  def handle_cast({:success, provider_id}, gen_state) do
    case :ets.lookup(@table, provider_id) do
      [{_id, :half_open, _count, _opened_at}] ->
        Logger.info("[circuit_breaker] provider=#{provider_id} state=closed (probe succeeded)")
        :ets.delete(@table, provider_id)

      [{_id, :closed, _count, _opened_at}] ->
        # Any success resets the consecutive failure streak.
        :ets.delete(@table, provider_id)

      _ ->
        :ok
    end

    {:noreply, gen_state}
  end

  @impl GenServer
  def handle_cast({:failure, provider_id}, gen_state) do
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@table, provider_id) do
      [] ->
        :ets.insert(@table, {provider_id, :closed, 1, nil})

      [{_id, :closed, count, _nil}] ->
        new_count = count + 1

        if new_count >= @failure_threshold do
          Logger.warning(
            "[circuit_breaker] provider=#{provider_id} state=open " <>
              "after #{new_count} consecutive failures"
          )

          :ets.insert(@table, {provider_id, :open, new_count, now})
        else
          :ets.insert(@table, {provider_id, :closed, new_count, nil})
        end

      [{_id, :open, count, _opened_at}] ->
        # Failure while still in the open window — reset the recovery clock.
        :ets.insert(@table, {provider_id, :open, count + 1, now})

      [{_id, :half_open, count, _opened_at}] ->
        Logger.warning("[circuit_breaker] provider=#{provider_id} state=open (probe failed)")
        :ets.insert(@table, {provider_id, :open, count + 1, now})
    end

    {:noreply, gen_state}
  end

  defp elapsed_ms(opened_at), do: System.monotonic_time(:millisecond) - opened_at
end
