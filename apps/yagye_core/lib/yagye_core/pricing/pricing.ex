defmodule YagyeCore.Pricing do
  @moduledoc false

  import Ecto.Query

  alias YagyeCore.Merchants.Schemas.Merchant
  alias YagyeCore.Pricing.Schemas.{FeeRecord, PricingPlan, PricingRule}
  alias YagyeCore.Repo

  # ── Public API ───────────────────────────────────────────────────────────────

  @doc """
  Computes the platform fee for a payment.

  Resolves the merchant's pricing plan, finds the most specific matching rule
  for the given method and amount, and returns the computed fee with full
  arithmetic detail.

  Returns `{:ok, fee_map}` or `{:error, :no_pricing_plan | :no_matching_rule}`.
  Errors are non-fatal — the caller decides whether to proceed without a fee record.
  """
  def compute_fee(merchant_id, amount, method, provider_code) do
    with {:ok, plan} <- resolve_plan(merchant_id),
         {:ok, rule} <- find_rule(plan.id, method, provider_code, amount) do
      fee = apply_rule(rule, amount)

      computation = %{
        gross_amount: amount,
        method: method,
        percentage_bps: rule.percentage_bps,
        fixed_amount: rule.fixed_amount,
        raw_fee: div(amount * rule.percentage_bps, 10_000) + rule.fixed_amount,
        minimum_fee: rule.minimum_fee,
        maximum_fee: rule.maximum_fee,
        applied_fee: fee,
        rule_specificity: rule.specificity
      }

      {:ok,
       %{
         amount: fee,
         currency: plan.currency,
         plan_id: plan.id,
         rule_id: rule.id,
         computation: computation
       }}
    end
  end

  @doc """
  Persists a fee record for a succeeded payment attempt.

  Idempotent on (source_type, source_id, party) — safe to call in a Multi.
  Returns `{:ok, fee_record}` or an Ecto error.
  """
  def record_fee(source_type, source_id, merchant_id, fee_result, mode) do
    FeeRecord.record_changeset(%FeeRecord{}, %{
      source_type: source_type,
      source_id: source_id,
      merchant_id: merchant_id,
      mode: mode,
      party: "platform",
      fee_kind: "psp_margin",
      amount: fee_result.amount,
      currency: fee_result.currency,
      pricing_plan_id: fee_result.plan_id,
      pricing_rule_id: fee_result.rule_id,
      computation: fee_result.computation
    })
    |> Repo.insert(
      on_conflict: :nothing,
      conflict_target: [:source_type, :source_id, :party]
    )
    |> case do
      {:ok, _} ->
        {:ok,
         Repo.get_by!(FeeRecord,
           source_type: source_type,
           source_id: source_id,
           party: "platform"
         )}

      {:error, _} = err ->
        err
    end
  end

  # ── Private ──────────────────────────────────────────────────────────────────

  defp resolve_plan(merchant_id) do
    plan_id =
      from(m in Merchant,
        where: m.id == ^merchant_id,
        select: m.pricing_plan_id
      )
      |> Repo.one()

    case plan_id do
      nil -> {:error, :no_pricing_plan}
      id -> {:ok, Repo.get!(PricingPlan, id)}
    end
  end

  defp find_rule(plan_id, method, provider_code, amount) do
    rule =
      from(r in PricingRule,
        where: r.plan_id == ^plan_id,
        where: is_nil(r.method) or r.method == ^(method || ""),
        where: is_nil(r.provider_code) or r.provider_code == ^(provider_code || ""),
        where: is_nil(r.amount_min) or r.amount_min <= ^amount,
        where: is_nil(r.amount_max) or r.amount_max >= ^amount,
        order_by: [desc: r.specificity],
        limit: 1
      )
      |> Repo.one()

    case rule do
      nil -> {:error, :no_matching_rule}
      r -> {:ok, r}
    end
  end

  defp apply_rule(rule, amount) do
    raw = div(amount * rule.percentage_bps, 10_000) + rule.fixed_amount
    raw = if rule.minimum_fee, do: max(raw, rule.minimum_fee), else: raw
    if rule.maximum_fee, do: min(raw, rule.maximum_fee), else: raw
  end
end
