defmodule YagyeCore.Shared.Types.YagyeMode do
  @moduledoc false
  use Ecto.Type

  @values ~w[simulation sandbox live]a

  @impl true
  def type, do: :yagye_mode

  @impl true
  def cast(value) when value in @values, do: {:ok, value}

  def cast(value) when is_binary(value) do
    atom = String.to_existing_atom(value)
    if atom in @values, do: {:ok, atom}, else: :error
  rescue
    ArgumentError -> :error
  end

  def cast(_), do: :error

  @impl true
  def load(value) when is_binary(value) do
    atom = String.to_existing_atom(value)
    if atom in @values, do: {:ok, atom}, else: :error
  rescue
    ArgumentError -> :error
  end

  def load(_), do: :error

  @impl true
  def dump(value) when value in @values, do: {:ok, Atom.to_string(value)}
  def dump(_), do: :error

  def values, do: @values
end
