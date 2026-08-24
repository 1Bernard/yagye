defmodule YagyeCore.Projections do
  @moduledoc false

  import Ecto.Query

  alias YagyeCore.Projections.Schemas.{DailyMetrics, MerchantBalance, PaymentSummary}
  alias YagyeCore.Repo

  # ── Public API ───────────────────────────────────────────────────────────────

  def merchant_balance(merchant_id) do
    balances =
      from(b in MerchantBalance,
        where: b.merchant_id == ^merchant_id
      )
      |> Repo.all()

    {:ok, balances}
  end

  def payment_summary(payment_id, merchant_id) do
    case Repo.get_by(PaymentSummary, payment_id: payment_id, merchant_id: merchant_id) do
      nil -> {:error, :not_found}
      summary -> {:ok, summary}
    end
  end

  def daily_metrics(merchant_id, date_from, date_to) do
    metrics =
      from(m in DailyMetrics,
        where:
          m.merchant_id == ^merchant_id and
            m.day >= ^date_from and
            m.day <= ^date_to,
        order_by: [asc: m.day, asc: m.currency, asc: m.mode]
      )
      |> Repo.all()

    {:ok, metrics}
  end
end
