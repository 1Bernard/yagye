defmodule YagyeCore.Float do
  @moduledoc false

  import Ecto.Query

  alias YagyeCore.Float.Schemas.MomoFloatBalance
  alias YagyeCore.Repo

  # ── Public API ───────────────────────────────────────────────────────────────

  @doc """
  Returns the float balance for a given network and mode, or nil.
  """
  def get_balance(network, mode) do
    case Repo.get_by(MomoFloatBalance, network: network, mode: mode) do
      nil -> {:error, :not_found}
      balance -> {:ok, balance}
    end
  end

  @doc """
  Lists all float balances.
  """
  def list_balances do
    Repo.all(from(b in MomoFloatBalance, order_by: [asc: :network, asc: :mode]))
  end

  @doc """
  Lists float balances that are below their low_water_mark.
  Used by alerting and top-up workflows.
  """
  def list_low_balances do
    from(b in MomoFloatBalance,
      where: b.balance < b.low_water_mark
    )
    |> Repo.all()
  end

  @doc """
  Upserts a float balance, setting last_synced_at to now.
  """
  def sync_balance(network, mode, balance, currency, low_water_mark) do
    %MomoFloatBalance{}
    |> MomoFloatBalance.upsert_changeset(%{
      network: network,
      mode: mode,
      balance: balance,
      currency: currency,
      low_water_mark: low_water_mark,
      last_synced_at: DateTime.utc_now()
    })
    |> Repo.insert(
      on_conflict: {:replace, [:balance, :low_water_mark, :last_synced_at]},
      conflict_target: [:network, :mode]
    )
  end

  @doc """
  Returns true if the balance for the given network+mode is below its low_water_mark.
  """
  def below_low_water?(network, mode) do
    case get_balance(network, mode) do
      {:ok, balance} -> MomoFloatBalance.below_low_water?(balance)
      {:error, :not_found} -> false
    end
  end
end
