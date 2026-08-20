defmodule YagyeCore.Shared.MoneyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias YagyeCore.Shared.Money

  # ---------------------------------------------------------------------------
  # Unit tests
  # ---------------------------------------------------------------------------

  describe "new/2" do
    test "upcases the currency code" do
      assert Money.new(100, "usd").currency == "USD"
    end

    test "stores amount as-is" do
      assert Money.new(999, "GHS").amount == 999
    end
  end

  describe "add/2" do
    test "adds two same-currency values" do
      assert Money.add(Money.new(100, "USD"), Money.new(50, "USD")) == Money.new(150, "USD")
    end

    test "raises on currency mismatch" do
      assert_raise FunctionClauseError, fn ->
        Money.add(Money.new(100, "USD"), Money.new(50, "GHS"))
      end
    end
  end

  describe "subtract/2" do
    test "subtracts same-currency values" do
      assert Money.subtract(Money.new(100, "USD"), Money.new(30, "USD")) == Money.new(70, "USD")
    end

    test "result can be negative" do
      assert Money.subtract(Money.new(10, "USD"), Money.new(30, "USD")) == Money.new(-20, "USD")
    end
  end

  describe "negate/1" do
    test "flips the sign" do
      assert Money.negate(Money.new(100, "USD")) == Money.new(-100, "USD")
    end

    test "negate of zero is zero" do
      assert Money.negate(Money.zero("USD")) == Money.zero("USD")
    end
  end

  describe "compare/2" do
    test "less than" do
      assert Money.compare(Money.new(1, "USD"), Money.new(2, "USD")) == :lt
    end

    test "greater than" do
      assert Money.compare(Money.new(2, "USD"), Money.new(1, "USD")) == :gt
    end

    test "equal" do
      assert Money.compare(Money.new(5, "USD"), Money.new(5, "USD")) == :eq
    end
  end

  describe "allocate/2 — unit examples" do
    test "equal split of 100 into 3 parts" do
      parts = Money.allocate(Money.new(100, "USD"), [1, 1, 1])
      assert Enum.map(parts, & &1.amount) == [34, 33, 33]
    end

    test "weighted split: 100 in ratio 1:2" do
      parts = Money.allocate(Money.new(100, "USD"), [1, 2])
      assert Enum.map(parts, & &1.amount) == [33, 67]
    end

    test "count shorthand produces equal-weight parts" do
      parts = Money.allocate(Money.new(100, "USD"), 4)
      assert Enum.map(parts, & &1.amount) == [25, 25, 25, 25]
    end

    test "zero splits into all zeros" do
      parts = Money.allocate(Money.zero("USD"), [1, 2, 3])
      assert Enum.all?(parts, &Money.zero?/1)
    end

    test "all parts carry the original currency" do
      parts = Money.allocate(Money.new(100, "GHS"), [3, 1])
      assert Enum.all?(parts, &(&1.currency == "GHS"))
    end

    test "negative amount is conserved" do
      parts = Money.allocate(Money.new(-100, "USD"), [1, 2])
      assert Enum.map(parts, & &1.amount) == [-33, -67]
    end
  end

  describe "multiply_bps/2" do
    test "150 bps of GHS 1000 is GHS 15 (150 pesewas)" do
      assert Money.multiply_bps(Money.new(1000, "GHS"), 150).amount == 15
    end

    test "10_000 bps is 100% — returns the original amount" do
      m = Money.new(999, "USD")
      assert Money.multiply_bps(m, 10_000) == m
    end

    test "0 bps always returns zero" do
      assert Money.multiply_bps(Money.new(50_000, "GHS"), 0) == Money.zero("GHS")
    end

    test "preserves currency" do
      assert Money.multiply_bps(Money.new(100, "NGN"), 200).currency == "NGN"
    end
  end

  describe "to_json/1 and from_json/1" do
    test "to_json produces the canonical wire shape" do
      assert Money.to_json(Money.new(1234, "GHS")) == %{"amount" => 1234, "currency" => "GHS"}
    end

    test "to_json never produces a float amount" do
      result = Money.to_json(Money.new(999, "USD"))
      assert is_integer(result["amount"])
    end

    test "from_json roundtrips with to_json" do
      m = Money.new(500, "GHS")
      assert Money.from_json(Money.to_json(m)) == {:ok, m}
    end

    test "from_json returns error on invalid input" do
      assert Money.from_json(%{"amount" => 12.34, "currency" => "GHS"}) ==
               {:error, :invalid_money}

      assert Money.from_json("1234 GHS") == {:error, :invalid_money}
      assert Money.from_json(nil) == {:error, :invalid_money}
    end
  end

  # ---------------------------------------------------------------------------
  # Property tests
  # ---------------------------------------------------------------------------

  defp money_gen do
    gen all(
          amount <- integer(-100_000..100_000),
          currency <- member_of(["USD", "GHS", "EUR", "NGN", "GBP"])
        ) do
      Money.new(amount, currency)
    end
  end

  defp ratios_gen do
    gen all(ratios <- list_of(positive_integer(), min_length: 1, max_length: 8)) do
      ratios
    end
  end

  property "allocate conserves every minor unit (sum of parts == original)" do
    check all(
            money <- money_gen(),
            ratios <- ratios_gen()
          ) do
      parts = Money.allocate(money, ratios)
      total = Enum.sum(Enum.map(parts, & &1.amount))
      assert total == money.amount
    end
  end

  property "allocate returns exactly as many parts as ratios" do
    check all(
            money <- money_gen(),
            ratios <- ratios_gen()
          ) do
      assert length(Money.allocate(money, ratios)) == length(ratios)
    end
  end

  property "allocate preserves currency on all parts" do
    check all(
            money <- money_gen(),
            ratios <- ratios_gen()
          ) do
      parts = Money.allocate(money, ratios)
      assert Enum.all?(parts, &(&1.currency == money.currency))
    end
  end

  property "add is commutative" do
    check all(
            a <- money_gen(),
            b <- map(money_gen(), &%{&1 | currency: a.currency})
          ) do
      assert Money.add(a, b) == Money.add(b, a)
    end
  end

  property "add with zero is identity" do
    check all(m <- money_gen()) do
      assert Money.add(m, Money.zero(m.currency)) == m
    end
  end

  property "add and negate cancel out" do
    check all(m <- money_gen()) do
      assert Money.add(m, Money.negate(m)) == Money.zero(m.currency)
    end
  end

  property "to_json/from_json roundtrip is lossless" do
    check all(m <- money_gen()) do
      assert Money.from_json(Money.to_json(m)) == {:ok, m}
    end
  end

  property "multiply_bps at 10_000 bps is identity" do
    check all(m <- money_gen()) do
      assert Money.multiply_bps(m, 10_000) == m
    end
  end
end
