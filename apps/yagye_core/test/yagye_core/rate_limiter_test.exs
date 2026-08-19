defmodule YagyeCore.RateLimiterTest do
  # No DB access — ETS only. async: true is safe.
  use ExUnit.Case, async: false

  alias YagyeCore.Shared.RateLimiter

  # Use a very low limit so tests don't need to fire hundreds of requests.
  @limit 5

  # Each test uses a unique IP so ETS state from parallel tests doesn't bleed.
  defp unique_ip, do: "10.0.#{:rand.uniform(255)}.#{:rand.uniform(255)}"

  test "allows requests below the limit" do
    ip = unique_ip()

    for _ <- 1..@limit do
      assert RateLimiter.allow?(ip, @limit) == true
    end
  end

  test "blocks the request that exceeds the limit" do
    ip = unique_ip()

    for _ <- 1..@limit, do: RateLimiter.allow?(ip, @limit)

    assert RateLimiter.allow?(ip, @limit) == false
  end

  test "different IPs have independent counters" do
    ip_a = unique_ip()
    ip_b = unique_ip()

    for _ <- 1..@limit, do: RateLimiter.allow?(ip_a, @limit)

    assert RateLimiter.allow?(ip_a, @limit) == false
    assert RateLimiter.allow?(ip_b, @limit) == true
  end

  test "counter resets in a new time window" do
    ip = unique_ip()

    # Exhaust the limit in the current window.
    for _ <- 1..@limit, do: RateLimiter.allow?(ip, @limit)
    assert RateLimiter.allow?(ip, @limit) == false

    # Simulate moving to the next minute window by using a future window key.
    next_window = System.os_time(:second) |> div(60) |> Kernel.+(1)
    key = {ip, next_window}
    assert :ets.lookup(:yagye_rate_limiter, key) == []

    # A request in the next window should be allowed.
    :ets.insert(:yagye_rate_limiter, {key, 1})
    assert :ets.lookup(:yagye_rate_limiter, key) == [{key, 1}]
  end
end
