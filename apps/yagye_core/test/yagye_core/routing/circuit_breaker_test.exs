defmodule YagyeCore.Routing.CircuitBreakerTest do
  use ExUnit.Case, async: true

  alias YagyeCore.Routing.CircuitBreaker

  # Each test starts its own isolated GenServer + ETS table so tests run async safely.
  setup do
    table = :"cb_test_#{System.unique_integer([:positive])}"
    name = :"cb_server_#{System.unique_integer([:positive])}"
    {:ok, pid} = CircuitBreaker.start_link(table: table, name: name)
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
    %{cb: name}
  end

  defp provider, do: "provider_#{System.unique_integer([:positive])}"

  defp open_circuit(cb, pid, count \\ 5) do
    for _ <- 1..count, do: CircuitBreaker.record_failure(pid, cb)
    # Allow the async casts to be processed before we read state.
    :sys.get_state(cb)
  end

  # ── default state ─────────────────────────────────────────────────────────

  describe "state/2 — default" do
    test "unknown provider is :closed", %{cb: cb} do
      assert CircuitBreaker.state(provider(), cb) == :closed
    end
  end

  # ── failure accumulation ──────────────────────────────────────────────────

  describe "record_failure/2" do
    test "stays :closed below threshold", %{cb: cb} do
      pid = provider()
      for _ <- 1..4, do: CircuitBreaker.record_failure(pid, cb)
      :sys.get_state(cb)
      assert CircuitBreaker.state(pid, cb) == :closed
    end

    test "opens after exactly the failure threshold", %{cb: cb} do
      pid = provider()
      open_circuit(cb, pid)
      assert CircuitBreaker.state(pid, cb) == :open
    end

    test "failure count keeps incrementing while open", %{cb: cb} do
      pid = provider()
      open_circuit(cb, pid)
      CircuitBreaker.record_failure(pid, cb)
      :sys.get_state(cb)
      assert CircuitBreaker.state(pid, cb) == :open
    end
  end

  # ── success resets streak ─────────────────────────────────────────────────

  describe "record_success/2" do
    test "resets consecutive failure streak while closed", %{cb: cb} do
      pid = provider()
      for _ <- 1..4, do: CircuitBreaker.record_failure(pid, cb)
      CircuitBreaker.record_success(pid, cb)
      :sys.get_state(cb)
      # One more failure after the reset should NOT open the circuit.
      CircuitBreaker.record_failure(pid, cb)
      :sys.get_state(cb)
      assert CircuitBreaker.state(pid, cb) == :closed
    end

    test "no-op for a provider with no recorded failures", %{cb: cb} do
      pid = provider()
      CircuitBreaker.record_success(pid, cb)
      :sys.get_state(cb)
      assert CircuitBreaker.state(pid, cb) == :closed
    end
  end

  # ── half-open probe ───────────────────────────────────────────────────────

  describe "half-open state (recovery period elapsed)" do
    # We override the recovery period by patching opened_at in ETS directly.

    defp force_half_open(cb, pid) do
      # Open the circuit normally, then backdatd the opened_at timestamp so the
      # recovery period appears to have elapsed.
      open_circuit(cb, pid)
      table = :sys.get_state(cb).table
      [{^pid, :open, count, _}] = :ets.lookup(table, pid)
      stale_at = System.monotonic_time(:millisecond) - 61_000
      :ets.insert(table, {pid, :open, count, stale_at})
    end

    test "reports :half_open when recovery period has elapsed", %{cb: cb} do
      pid = provider()
      force_half_open(cb, pid)
      assert CircuitBreaker.state(pid, cb) == :half_open
    end

    test "probe success closes the circuit", %{cb: cb} do
      pid = provider()
      force_half_open(cb, pid)
      assert CircuitBreaker.state(pid, cb) == :half_open

      CircuitBreaker.record_success(pid, cb)
      :sys.get_state(cb)
      assert CircuitBreaker.state(pid, cb) == :closed
    end

    test "probe failure re-opens the circuit", %{cb: cb} do
      pid = provider()
      force_half_open(cb, pid)
      assert CircuitBreaker.state(pid, cb) == :half_open

      CircuitBreaker.record_failure(pid, cb)
      :sys.get_state(cb)
      # Re-opened resets the recovery clock, so it is :open (not :half_open) again.
      assert CircuitBreaker.state(pid, cb) == :open
    end
  end

  # ── open_provider_ids/1 ───────────────────────────────────────────────────

  describe "open_provider_ids/1" do
    test "returns empty list when no circuits are open", %{cb: cb} do
      assert CircuitBreaker.open_provider_ids(cb) == []
    end

    test "includes only fully-open providers, not closed or half-open", %{cb: cb} do
      open_pid = provider()
      closed_pid = provider()
      half_open_pid = provider()

      # Open one normally.
      open_circuit(cb, open_pid)

      # Leave one closed (below threshold).
      for _ <- 1..3, do: CircuitBreaker.record_failure(closed_pid, cb)
      :sys.get_state(cb)

      # Force one into half-open by back-dating.
      open_circuit(cb, half_open_pid)
      table = :sys.get_state(cb).table
      [{^half_open_pid, :open, count, _}] = :ets.lookup(table, half_open_pid)

      :ets.insert(
        table,
        {half_open_pid, :open, count, System.monotonic_time(:millisecond) - 61_000}
      )

      open_ids = CircuitBreaker.open_provider_ids(cb)
      assert open_pid in open_ids
      refute closed_pid in open_ids
      refute half_open_pid in open_ids
    end

    test "returns multiple open providers", %{cb: cb} do
      p1 = provider()
      p2 = provider()
      open_circuit(cb, p1)
      open_circuit(cb, p2)

      open_ids = CircuitBreaker.open_provider_ids(cb)
      assert p1 in open_ids
      assert p2 in open_ids
    end
  end

  # ── isolation between providers ───────────────────────────────────────────

  describe "isolation" do
    test "failures on one provider do not affect another", %{cb: cb} do
      bad = provider()
      good = provider()

      open_circuit(cb, bad)
      CircuitBreaker.record_success(good, cb)
      :sys.get_state(cb)

      assert CircuitBreaker.state(bad, cb) == :open
      assert CircuitBreaker.state(good, cb) == :closed
    end
  end
end
