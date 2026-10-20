defmodule YagyeCore.Pricing do
  @moduledoc false

  require Logger

  import Ecto.Query

  alias YagyeCore.Merchants.Schemas.Merchant
  alias YagyeCore.Pricing.Schemas.{FeeRecord, PlatformFeeInvoice, PricingPlan, PricingRule}
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

  def get_merchant_plan(merchant_id) do
    plan_id =
      from(m in Merchant, where: m.id == ^merchant_id, select: m.pricing_plan_id)
      |> Repo.one()

    case plan_id do
      nil ->
        {:error, :no_pricing_plan}

      id ->
        rules_q =
          from(r in PricingRule, where: is_nil(r.deleted_at), order_by: [desc: r.specificity])

        plan = Repo.get!(PricingPlan, id) |> Repo.preload(rules: rules_q)
        {:ok, plan}
    end
  end

  def list_fee_invoices(merchant_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    invoices =
      from(i in PlatformFeeInvoice,
        where: i.merchant_id == ^merchant_id,
        order_by: [desc: i.period_start],
        limit: ^limit,
        offset: ^offset
      )
      |> Repo.all()

    {:ok, invoices}
  end

  def list_fee_records(merchant_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    records =
      from(f in FeeRecord,
        where: f.merchant_id == ^merchant_id,
        order_by: [desc: f.inserted_at],
        limit: ^limit,
        offset: ^offset
      )
      |> Repo.all()

    {:ok, records}
  end

  def list_plans(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    plans =
      from(p in PricingPlan,
        order_by: [desc: p.inserted_at],
        limit: ^limit,
        offset: ^offset
      )
      |> Repo.all()

    {:ok, plans}
  end

  def create_plan(attrs) do
    %PricingPlan{}
    |> PricingPlan.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Activates a pricing plan so it can be assigned to merchants and used in fee computation.

  Enforces SoD: the actor who activates cannot be the same as the one who created.
  Returns `{:ok, plan}` or `{:error, :not_found | :already_active | changeset}`.
  """
  def activate_plan(public_id, actor) do
    case Repo.get_by(PricingPlan, public_id: public_id) do
      nil ->
        {:error, :not_found}

      %PricingPlan{status: "active"} = plan ->
        {:ok, plan}

      plan ->
        plan
        |> PricingPlan.activate_changeset(actor)
        |> Repo.update()
    end
  end

  def get_plan(public_id) do
    rules_q = from(r in PricingRule, where: is_nil(r.deleted_at), order_by: [desc: r.specificity])

    case Repo.get_by(PricingPlan, public_id: public_id) do
      nil -> {:error, :not_found}
      plan -> {:ok, Repo.preload(plan, rules: rules_q)}
    end
  end

  def delete_rule(rule_id) do
    case Repo.get(PricingRule, rule_id) do
      nil -> {:error, :not_found}
      %PricingRule{deleted_at: deleted_at} when not is_nil(deleted_at) -> {:error, :not_found}
      rule -> rule |> PricingRule.delete_changeset() |> Repo.update()
    end
  end

  def assign_plan(merchant_id, plan_public_id) do
    case Repo.get_by(PricingPlan, public_id: plan_public_id) do
      nil ->
        {:error, :plan_not_found}

      %PricingPlan{status: status} when status != "active" ->
        {:error, :plan_not_active}

      plan ->
        Repo.get!(Merchant, merchant_id)
        |> Ecto.Changeset.change(pricing_plan_id: plan.id)
        |> Repo.update()
        |> case do
          {:ok, _merchant} -> {:ok, plan}
          {:error, cs} -> {:error, cs}
        end
    end
  end

  def create_rule(plan_id, attrs, actor) do
    %PricingRule{}
    |> PricingRule.create_changeset(Map.merge(attrs, %{plan_id: plan_id, created_by: actor}))
    |> Repo.insert()
  end

  def approve_rule(%PricingRule{} = rule, actor) do
    rule
    |> PricingRule.approve_changeset(actor)
    |> Repo.update()
  end

  def initiate_write_off_invoice(%PlatformFeeInvoice{} = invoice, actor) do
    invoice
    |> PlatformFeeInvoice.initiate_write_off_changeset(actor)
    |> Repo.update()
  end

  def approve_write_off_invoice(%PlatformFeeInvoice{} = invoice, actor) do
    invoice
    |> PlatformFeeInvoice.approve_write_off_changeset(actor)
    |> Repo.update()
  end

  @doc """
  Reverses the PSP margin fee for a refund.

  Finds the original fee for the payment attempt, computes a proportional
  reversal amount (refund_amount / payment_amount × original_fee), and inserts
  a new fee_record with fee_kind "psp_margin_reversal". Idempotent: if a
  reversal already exists for this refund_id it is a no-op.

  Non-fatal by design — callers should log and continue if this returns an error.
  """
  def reverse_fee(payment_attempt_id, merchant_id, refund_id, refund_amount) do
    with {:ok, original} <- find_fee_for_attempt(payment_attempt_id),
         false <- already_reversed?(refund_id) do
      attempt_amount = get_in(original.computation, ["gross_amount"]) || 0
      reversal_amount = compute_reversal_amount(refund_amount, attempt_amount, original.amount)

      %FeeRecord{}
      |> FeeRecord.reversal_changeset(%{
        source_type: "refund",
        source_id: refund_id,
        merchant_id: merchant_id,
        mode: original.mode,
        party: original.party,
        amount: reversal_amount,
        currency: original.currency,
        computation: %{
          original_fee: original.amount,
          refund_amount: refund_amount,
          attempt_amount: attempt_amount,
          reversal_amount: reversal_amount
        },
        reversal_of_id: original.id
      })
      |> Repo.insert()
    else
      {:error, :no_fee_record} -> {:ok, :no_fee_to_reverse}
      true -> {:ok, :already_reversed}
      err -> err
    end
  end

  @doc """
  Aggregates fee revenue by period for ops reporting.

  Returns net fee revenue (original fees minus reversals), grouped by month.
  """
  def fee_revenue_summary(opts \\ []) do
    merchant_id = Keyword.get(opts, :merchant_id)
    from_date = Keyword.get(opts, :from_date)
    to_date = Keyword.get(opts, :to_date)

    q =
      from(f in FeeRecord,
        where: f.party == "platform",
        select: %{
          fee_kind: f.fee_kind,
          currency: f.currency,
          total_amount: sum(f.amount),
          count: count(f.id)
        },
        group_by: [f.fee_kind, f.currency]
      )

    q = if merchant_id, do: where(q, [f], f.merchant_id == ^merchant_id), else: q
    q = if from_date, do: where(q, [f], f.inserted_at >= ^from_date), else: q
    q = if to_date, do: where(q, [f], f.inserted_at <= ^to_date), else: q

    rows = Repo.all(q)

    gross = rows |> Enum.filter(&(&1.fee_kind == "psp_margin")) |> Enum.sum_by(& &1.total_amount)

    reversals =
      rows
      |> Enum.filter(&(&1.fee_kind == "psp_margin_reversal"))
      |> Enum.sum_by(& &1.total_amount)

    {:ok,
     %{
       gross_fee_revenue: gross,
       total_reversals: reversals,
       net_fee_revenue: gross - reversals,
       breakdown: rows
     }}
  end

  # ── Private ──────────────────────────────────────────────────────────────────

  defp resolve_plan(merchant_id) do
    now = DateTime.utc_now()

    plan_id =
      from(m in Merchant,
        where: m.id == ^merchant_id,
        select: m.pricing_plan_id
      )
      |> Repo.one()

    case plan_id do
      nil ->
        {:error, :no_pricing_plan}

      id ->
        plan =
          from(p in PricingPlan,
            where: p.id == ^id,
            where: p.status in ["active", "archived"],
            where: p.effective_from <= ^now,
            where: is_nil(p.effective_to) or p.effective_to > ^now
          )
          |> Repo.one()

        case plan do
          nil -> {:error, :no_pricing_plan}
          p -> {:ok, p}
        end
    end
  end

  defp find_rule(plan_id, method, provider_code, amount) do
    rule =
      from(r in PricingRule,
        where: r.plan_id == ^plan_id,
        where: is_nil(r.deleted_at),
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

  defp find_fee_for_attempt(payment_attempt_id) do
    case Repo.get_by(FeeRecord,
           source_type: "payment_attempt",
           source_id: payment_attempt_id,
           party: "platform"
         ) do
      nil -> {:error, :no_fee_record}
      fee -> {:ok, fee}
    end
  end

  defp already_reversed?(refund_id) do
    Repo.exists?(
      from(f in FeeRecord,
        where:
          f.source_type == "refund" and f.source_id == ^refund_id and
            f.fee_kind == "psp_margin_reversal"
      )
    )
  end

  defp compute_reversal_amount(refund_amount, attempt_amount, original_fee)
       when attempt_amount > 0 do
    div(refund_amount * original_fee, attempt_amount)
  end

  defp compute_reversal_amount(_refund_amount, _attempt_amount, original_fee), do: original_fee
end
