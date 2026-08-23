defmodule YagyeCore.Pricing.PricingTest do
  use YagyeCore.DataCase, async: true

  alias YagyeCore.Fixtures
  alias YagyeCore.Pricing
  alias YagyeCore.Pricing.Schemas.{FeeRecord, PricingPlan, PricingRule}
  alias YagyeCore.Repo

  # ── Fixtures ─────────────────────────────────────────────────────────────────

  defp plan_fixture(attrs \\ %{}) do
    attrs =
      Map.merge(
        %{
          name: "Standard GHS #{System.unique_integer([:positive])}",
          version: 1,
          currency: "GHS",
          fee_mode: "deducted",
          effective_from: DateTime.utc_now()
        },
        attrs
      )

    %PricingPlan{} |> PricingPlan.create_changeset(attrs) |> Repo.insert!()
  end

  defp rule_fixture(plan, attrs \\ %{}) do
    attrs =
      Map.merge(
        %{
          plan_id: plan.id,
          percentage_bps: 150,
          fixed_amount: 20
        },
        attrs
      )

    %PricingRule{} |> PricingRule.create_changeset(attrs) |> Repo.insert!()
  end

  defp merchant_with_plan(plan) do
    merchant = Fixtures.approved_merchant_fixture()

    Repo.update_all(
      YagyeCore.Merchants.Schemas.Merchant |> where([m], m.id == ^merchant.id),
      set: [pricing_plan_id: plan.id]
    )

    Repo.get!(YagyeCore.Merchants.Schemas.Merchant, merchant.id)
  end

  # ── compute_fee/4 ─────────────────────────────────────────────────────────────

  test "computes correct fee with percentage + fixed" do
    plan = plan_fixture()
    _rule = rule_fixture(plan, %{percentage_bps: 150, fixed_amount: 20})
    merchant = merchant_with_plan(plan)

    {:ok, fee} = Pricing.compute_fee(merchant.id, 10_000, "card", nil)

    # 1.5% of 10_000 = 150 (integer div) + 20 fixed = 170
    assert fee.amount == 170
    assert fee.currency == "GHS"
    assert fee.computation.percentage_bps == 150
    assert fee.computation.fixed_amount == 20
  end

  test "returns :no_pricing_plan when merchant has no plan" do
    merchant = Fixtures.approved_merchant_fixture()
    assert {:error, :no_pricing_plan} = Pricing.compute_fee(merchant.id, 10_000, "card", nil)
  end

  test "returns :no_matching_rule when no rule covers the method" do
    plan = plan_fixture()
    _rule = rule_fixture(plan, %{method: "card"})
    merchant = merchant_with_plan(plan)

    assert {:error, :no_matching_rule} =
             Pricing.compute_fee(merchant.id, 10_000, "mobile_money", nil)
  end

  test "method-specific rule beats catchall by specificity" do
    plan = plan_fixture()
    # Catchall: 0 specificity (percentage_bps 100 = 1%)
    _catchall = rule_fixture(plan, %{percentage_bps: 100, fixed_amount: 0})
    # Method-specific: specificity 1 (percentage_bps 200 = 2%)
    _specific =
      rule_fixture(plan, %{method: "mobile_money", percentage_bps: 200, fixed_amount: 0})

    merchant = merchant_with_plan(plan)

    {:ok, fee} = Pricing.compute_fee(merchant.id, 10_000, "mobile_money", nil)

    # Specific rule wins: 2% of 10_000 = 200
    assert fee.amount == 200
  end

  test "respects maximum_fee cap" do
    plan = plan_fixture()
    _rule = rule_fixture(plan, %{percentage_bps: 300, fixed_amount: 0, maximum_fee: 50})
    merchant = merchant_with_plan(plan)

    {:ok, fee} = Pricing.compute_fee(merchant.id, 10_000, "card", nil)

    # 3% of 10_000 = 300, capped at 50
    assert fee.amount == 50
  end

  test "respects minimum_fee floor" do
    plan = plan_fixture()
    _rule = rule_fixture(plan, %{percentage_bps: 10, fixed_amount: 0, minimum_fee: 100})
    merchant = merchant_with_plan(plan)

    {:ok, fee} = Pricing.compute_fee(merchant.id, 100, "card", nil)

    # 0.1% of 100 = 0, floored to 100
    assert fee.amount == 100
  end

  # ── record_fee/5 ──────────────────────────────────────────────────────────────

  test "records a fee_record for a payment attempt" do
    plan = plan_fixture()
    _rule = rule_fixture(plan)
    merchant = merchant_with_plan(plan)
    {:ok, fee} = Pricing.compute_fee(merchant.id, 5_000, "card", nil)

    attempt_id = Ecto.UUID.generate()

    {:ok, record} =
      Pricing.record_fee("payment_attempt", attempt_id, merchant.id, fee, "simulation")

    assert record.source_type == "payment_attempt"
    assert record.source_id == attempt_id
    assert record.party == "platform"
    assert record.fee_kind == "psp_margin"
    assert record.amount == fee.amount
  end

  test "record_fee is idempotent on same source" do
    plan = plan_fixture()
    _rule = rule_fixture(plan)
    merchant = merchant_with_plan(plan)
    {:ok, fee} = Pricing.compute_fee(merchant.id, 5_000, "card", nil)
    attempt_id = Ecto.UUID.generate()

    {:ok, first} =
      Pricing.record_fee("payment_attempt", attempt_id, merchant.id, fee, "simulation")

    {:ok, second} =
      Pricing.record_fee("payment_attempt", attempt_id, merchant.id, fee, "simulation")

    assert first.id == second.id
    assert Repo.aggregate(FeeRecord, :count) == 1
  end
end
