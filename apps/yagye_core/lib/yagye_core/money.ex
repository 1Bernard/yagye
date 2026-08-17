defmodule Yagye.Money do
  @moduledoc false

  @enforce_keys [:amount, :currency]
  defstruct [:amount, :currency]

  @type t :: %__MODULE__{amount: integer(), currency: String.t()}

  def new(amount, currency) when is_integer(amount) and is_binary(currency) do
    %__MODULE__{amount: amount, currency: String.upcase(currency)}
  end

  def zero(currency) when is_binary(currency), do: new(0, currency)

  def add(%__MODULE__{currency: c} = a, %__MODULE__{currency: c} = b),
    do: %__MODULE__{amount: a.amount + b.amount, currency: c}

  def subtract(%__MODULE__{currency: c} = a, %__MODULE__{currency: c} = b),
    do: %__MODULE__{amount: a.amount - b.amount, currency: c}

  def multiply(%__MODULE__{} = m, scalar) when is_integer(scalar),
    do: %__MODULE__{m | amount: m.amount * scalar}

  # Multiply by basis points (100 bps = 1%). Used for fee calculation.
  # 1500 bps applied to GHS 1000 = GHS 15.00 (150 pesewas).
  # Uses floor division — rounding modes live on pricing_rules, not here.
  def multiply_bps(%__MODULE__{amount: amount, currency: currency}, bps)
      when is_integer(bps) and bps >= 0 do
    %__MODULE__{amount: Integer.floor_div(amount * bps, 10_000), currency: currency}
  end

  def negate(%__MODULE__{} = m), do: %__MODULE__{m | amount: -m.amount}

  def zero?(%__MODULE__{amount: 0}), do: true
  def zero?(%__MODULE__{}), do: false

  def positive?(%__MODULE__{amount: a}), do: a > 0
  def negative?(%__MODULE__{amount: a}), do: a < 0

  def compare(%__MODULE__{currency: c, amount: a}, %__MODULE__{currency: c, amount: b}) do
    cond do
      a < b -> :lt
      a > b -> :gt
      true -> :eq
    end
  end

  # Split money across integer ratios using the largest-remainder algorithm.
  # No minor unit is ever created or lost: Enum.sum(parts) == original amount.
  def allocate(%__MODULE__{} = money, count) when is_integer(count) and count > 0,
    do: allocate(money, List.duplicate(1, count))

  def allocate(%__MODULE__{amount: amount, currency: currency}, ratios)
      when is_list(ratios) and ratios != [] do
    total = Enum.sum(ratios)

    floor_allocs = Enum.map(ratios, fn r -> Integer.floor_div(amount * r, total) end)

    # How many +1 units remain after flooring (always >= 0 because floor rounds down)
    remainder = amount - Enum.sum(floor_allocs)

    # Rank slots by descending fractional part; top `remainder` slots each get +1
    bump_set =
      ratios
      |> Enum.with_index()
      |> Enum.map(fn {r, i} ->
        # Non-negative modulo gives the fractional numerator in [0, total)
        frac = rem(rem(amount * r, total) + total, total)
        {frac, i}
      end)
      |> Enum.sort_by(fn {frac, _} -> -frac end)
      |> Enum.take(remainder)
      |> Enum.map(fn {_, i} -> i end)
      |> MapSet.new()

    floor_allocs
    |> Enum.with_index()
    |> Enum.map(fn {alloc, i} ->
      bump = if MapSet.member?(bump_set, i), do: 1, else: 0
      %__MODULE__{amount: alloc + bump, currency: currency}
    end)
  end

  # Canonical wire format: {"amount": 1234, "currency": "GHS"}.
  # Never 12.34. The float representation of money is always wrong.
  def to_json(%__MODULE__{amount: amount, currency: currency}) do
    %{"amount" => amount, "currency" => currency}
  end

  def from_json(%{"amount" => amount, "currency" => currency})
      when is_integer(amount) and is_binary(currency) do
    {:ok, new(amount, currency)}
  end

  def from_json(_), do: {:error, :invalid_money}
end

defmodule Yagye.Money.EctoType do
  @moduledoc false

  # Ecto.Type for Money stored as a JSONB column.
  # For the standard two-column pattern (bigint + char(3)), declare two
  # separate Ecto fields. This type is for JSONB storage and API casting.
  use Ecto.Type

  @impl true
  def type, do: :map

  @impl true
  def cast(%Yagye.Money{} = money), do: {:ok, money}

  def cast(%{"amount" => amount, "currency" => currency})
      when is_integer(amount) and is_binary(currency) do
    {:ok, Yagye.Money.new(amount, currency)}
  end

  def cast(_), do: :error

  @impl true
  def load(%{"amount" => amount, "currency" => currency})
      when is_integer(amount) and is_binary(currency) do
    {:ok, Yagye.Money.new(amount, currency)}
  end

  def load(_), do: :error

  @impl true
  def dump(%Yagye.Money{} = money), do: {:ok, Yagye.Money.to_json(money)}
  def dump(_), do: :error
end
