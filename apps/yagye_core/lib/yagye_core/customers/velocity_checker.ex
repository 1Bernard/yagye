defmodule YagyeCore.Customers.VelocityChecker do
  @moduledoc false

  import Ecto.Query

  alias YagyeCore.Customers.Schemas.{Customer, VelocityLimit}
  alias YagyeCore.Merchants.Schemas.Merchant
  alias YagyeCore.Payments.Schemas.Payment
  alias YagyeCore.Repo

  # ── Public API ───────────────────────────────────────────────────────────────

  @doc """
  Checks both merchant and customer velocity limits before a payment is created.

  Returns `:ok` or `{:error, reason}` where reason is one of:
    :single_txn_limit_exceeded | :daily_limit_exceeded | :monthly_limit_exceeded

  Uses hardcoded defaults from VelocityLimit.default_limits/0 when no DB row
  exists — the system works without pre-seeded data.
  """
  def check(merchant_id, customer_id, amount, method, currency) do
    with {:ok, merchant_risk} <- load_merchant_risk(merchant_id),
         :ok <-
           check_entity(
             "merchant",
             merchant_risk,
             method,
             currency,
             merchant_id,
             customer_id,
             amount,
             :merchant
           ) do
      check_customer_limits(customer_id, method, currency, amount)
    end
  end

  # ── Private ──────────────────────────────────────────────────────────────────

  defp load_merchant_risk(merchant_id) do
    from(m in Merchant, where: m.id == ^merchant_id, select: {m.id, m.risk_rating})
    |> Repo.one()
    |> case do
      nil -> {:error, :merchant_not_found}
      {_id, risk} -> {:ok, risk || "medium"}
    end
  end

  defp check_entity(
         "merchant",
         risk_tier,
         method,
         currency,
         merchant_id,
         _customer_id,
         amount,
         _role
       ) do
    limit = load_limit("merchant", risk_tier, method, currency)

    with :ok <- check_single(amount, limit.max_single_txn),
         :ok <-
           check_period(merchant_id, nil, currency, "live", day_start(), limit.max_daily, :daily) do
      check_period(merchant_id, nil, currency, "live", month_start(), limit.max_monthly, :monthly)
    end
  end

  defp check_customer_limits(nil, _method, _currency, _amount), do: :ok

  defp check_customer_limits(customer_id, method, currency, amount) do
    kyc_tier =
      from(c in Customer, where: c.id == ^customer_id, select: c.kyc_tier)
      |> Repo.one()

    tier = kyc_tier || "tier_1"
    limit = load_limit("customer", tier, method, currency)

    with :ok <- check_single(amount, limit.max_single_txn),
         :ok <-
           check_customer_period(
             customer_id,
             currency,
             "live",
             day_start(),
             limit.max_daily,
             :daily
           ) do
      check_customer_period(
        customer_id,
        currency,
        "live",
        month_start(),
        limit.max_monthly,
        :monthly
      )
    end
  end

  defp check_single(_amount, nil), do: :ok

  defp check_single(amount, max) do
    if amount <= max, do: :ok, else: {:error, :single_txn_limit_exceeded}
  end

  defp check_period(merchant_id, _customer_id, currency, mode, since, max, period)
       when not is_nil(max) do
    volume =
      from(p in Payment,
        where:
          p.merchant_id == ^merchant_id and
            p.currency == ^currency and
            p.mode == ^mode and
            p.state == "succeeded" and
            p.inserted_at >= ^since,
        select: coalesce(sum(p.amount), 0)
      )
      |> Repo.one()
      |> to_integer()

    # sobelow_skip ["DOS.BinToAtom"] — period is always a compile-time atom (:daily/:monthly)
    reason = :"#{period}_limit_exceeded"
    if volume < max, do: :ok, else: {:error, reason}
  end

  defp check_period(_, _, _, _, _, nil, _period), do: :ok

  defp check_customer_period(customer_id, currency, mode, since, max, period)
       when not is_nil(max) do
    volume =
      from(p in Payment,
        where:
          p.customer_id == ^customer_id and
            p.currency == ^currency and
            p.mode == ^mode and
            p.state == "succeeded" and
            p.inserted_at >= ^since,
        select: coalesce(sum(p.amount), 0)
      )
      |> Repo.one()
      |> to_integer()

    # sobelow_skip ["DOS.BinToAtom"] — period is always a compile-time atom (:daily/:monthly)
    reason = :"#{period}_limit_exceeded"
    if volume < max, do: :ok, else: {:error, reason}
  end

  defp check_customer_period(_, _, _, _, nil, _period), do: :ok

  defp to_integer(nil), do: 0
  defp to_integer(%Decimal{} = d), do: Decimal.to_integer(d)
  defp to_integer(n) when is_integer(n), do: n

  defp load_limit(entity_type, risk_tier, method, currency) do
    query_limit(entity_type, risk_tier, method || "any", currency) ||
      fallback_to_any(entity_type, risk_tier, method, currency) ||
      hardcoded_default(entity_type, risk_tier, method)
  end

  defp fallback_to_any(_entity_type, _risk_tier, method, _currency)
       when is_nil(method) or method == "any",
       do: nil

  defp fallback_to_any(entity_type, risk_tier, _method, currency) do
    query_limit(entity_type, risk_tier, "any", currency)
  end

  defp query_limit(entity_type, risk_tier, payment_method, currency) do
    from(v in VelocityLimit,
      where:
        v.entity_type == ^entity_type and
          v.risk_tier == ^risk_tier and
          v.payment_method == ^payment_method and
          v.currency == ^currency
    )
    |> Repo.one()
  end

  defp hardcoded_default(entity_type, risk_tier, method) do
    VelocityLimit.default_limits()
    |> Enum.find(fn l ->
      l.entity_type == entity_type &&
        l.risk_tier == risk_tier &&
        (l.payment_method == method || l.payment_method == "any")
    end)
    |> case do
      nil ->
        %{max_single_txn: nil, max_daily: nil, max_monthly: nil}

      map ->
        struct!(VelocityLimit, map)
    end
  end

  defp day_start do
    now = DateTime.utc_now()
    %{now | hour: 0, minute: 0, second: 0, microsecond: {0, 6}}
  end

  defp month_start do
    now = DateTime.utc_now()
    %{now | day: 1, hour: 0, minute: 0, second: 0, microsecond: {0, 6}}
  end
end
