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
end
