defmodule YagyeCore.FX do
  @moduledoc false

  import Ecto.Query

  alias YagyeCore.Fx.Schemas.FxRate
  alias YagyeCore.Repo

  # ── Public API ───────────────────────────────────────────────────────────────

  @doc """
  Returns the most recent active (non-expired) rate for a currency pair.
  Returns {:error, :not_found} when no rate exists or all are expired.
  """
  def get_rate(base, quote_currency) do
    now = DateTime.utc_now()

    from(r in FxRate,
      where:
        r.base == ^base and
          r.quote == ^quote_currency and
          r.expires_at > ^now,
      order_by: [desc: r.quoted_at],
      limit: 1
    )
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      rate -> {:ok, rate}
    end
  end

  @doc """
  Inserts a new FX rate snapshot. Each snapshot is a new row;
  stale rates expire naturally via expires_at.
  """
  def insert_rate(attrs) do
    %FxRate{}
    |> FxRate.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Converts an integer amount (minor units) from base to quote currency
  using the most recent non-expired rate.
  Returns {:ok, converted_amount} or {:error, :no_rate}.
  """
  def convert(amount, currency, currency, _), do: {:ok, amount}

  def convert(amount, base, quote_currency, _mode) do
    case get_rate(base, quote_currency) do
      {:ok, rate} ->
        converted =
          amount
          |> Decimal.new()
          |> Decimal.mult(rate.rate)
          |> Decimal.round(0, :half_up)
          |> Decimal.to_integer()

        {:ok, converted}

      {:error, :not_found} ->
        {:error, :no_rate}
    end
  end
end
