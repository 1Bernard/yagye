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
          effective_from: DateTime.utc_now(),
          created_by: "ops_user_1"
        },
        attrs
      )

    %PricingPlan{} |> PricingPlan.create_changeset(attrs) |> Repo.insert!()
  end

  defp active_plan_fixture(attrs \\ %{}) do
    plan = plan_fixture(attrs)
    plan |> PricingPlan.activate_changeset("ops_user_2") |> Repo.update!()
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

  defp merchant_with_active_plan(extra_plan_attrs \\ %{}) do
    plan = active_plan_fixture(extra_plan_attrs)

    merchant_with_plan(plan)
    |> then(fn m -> {m, plan} end)
  end

  # ── compute_fee/4 ─────────────────────────────────────────────────────────────

  test "computes correct fee with percentage + fixed" do
    {merchant, plan} = merchant_with_active_plan()
    _rule = rule_fixture(plan, %{percentage_bps: 150, fixed_amount: 20})

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

  test "draft plan is not used for fee computation" do
    plan = plan_fixture()
    _rule = rule_fixture(plan, %{percentage_bps: 150, fixed_amount: 0})
    merchant = merchant_with_plan(plan)

    assert {:error, :no_pricing_plan} = Pricing.compute_fee(merchant.id, 10_000, "card", nil)
  end

  test "plan with future effective_from is not used for fee computation" do
    future = DateTime.add(DateTime.utc_now(), 86_400, :second)
    {merchant, plan} = merchant_with_active_plan(%{effective_from: future})
    _rule = rule_fixture(plan, %{percentage_bps: 150})

    assert {:error, :no_pricing_plan} = Pricing.compute_fee(merchant.id, 10_000, "card", nil)
  end

  test "plan with past effective_to is not used for fee computation" do
    past_from = DateTime.add(DateTime.utc_now(), -7200, :second)
    past_to = DateTime.add(DateTime.utc_now(), -3600, :second)

    {merchant, plan} =
      merchant_with_active_plan(%{effective_from: past_from, effective_to: past_to})

    _rule = rule_fixture(plan, %{percentage_bps: 150})

    assert {:error, :no_pricing_plan} = Pricing.compute_fee(merchant.id, 10_000, "card", nil)
  end

  test "returns :no_matching_rule when no rule covers the method" do
    {merchant, plan} = merchant_with_active_plan()
    _rule = rule_fixture(plan, %{method: "card"})

    assert {:error, :no_matching_rule} =
             Pricing.compute_fee(merchant.id, 10_000, "mobile_money", nil)
  end

  test "method-specific rule beats catchall by specificity" do
    {merchant, plan} = merchant_with_active_plan()
    _catchall = rule_fixture(plan, %{percentage_bps: 100, fixed_amount: 0})

    _specific =
      rule_fixture(plan, %{method: "mobile_money", percentage_bps: 200, fixed_amount: 0})

    {:ok, fee} = Pricing.compute_fee(merchant.id, 10_000, "mobile_money", nil)

    # Specific rule wins: 2% of 10_000 = 200
    assert fee.amount == 200
  end

  test "provider+method rule beats method-only by specificity" do
    {merchant, plan} = merchant_with_active_plan()

    _method_only =
      rule_fixture(plan, %{method: "mobile_money", percentage_bps: 100, fixed_amount: 0})

    _provider =
      rule_fixture(plan, %{
        method: "mobile_money",
        provider_code: "MTN_MOMO_GH",
        percentage_bps: 200,
        fixed_amount: 0
      })

    {:ok, fee} = Pricing.compute_fee(merchant.id, 10_000, "mobile_money", "MTN_MOMO_GH")

    # Provider-specific wins: 2% of 10_000 = 200
    assert fee.amount == 200
  end

  test "amount-range rule only matches within range" do
    {merchant, plan} = merchant_with_active_plan()
    _catchall = rule_fixture(plan, %{percentage_bps: 100, fixed_amount: 0})

    _range_rule =
      rule_fixture(plan, %{
        amount_min: 5_000,
        amount_max: 20_000,
        percentage_bps: 300,
        fixed_amount: 0
      })

    {:ok, in_range} = Pricing.compute_fee(merchant.id, 10_000, "card", nil)
    {:ok, out_range} = Pricing.compute_fee(merchant.id, 1_000, "card", nil)

    # 3% of 10_000
    assert in_range.amount == 300
    # 1% of 1_000 (catchall)
    assert out_range.amount == 10
  end

  test "respects maximum_fee cap" do
    {merchant, plan} = merchant_with_active_plan()
    _rule = rule_fixture(plan, %{percentage_bps: 300, fixed_amount: 0, maximum_fee: 50})

    {:ok, fee} = Pricing.compute_fee(merchant.id, 10_000, "card", nil)

    assert fee.amount == 50
  end

  test "respects minimum_fee floor" do
    {merchant, plan} = merchant_with_active_plan()
    _rule = rule_fixture(plan, %{percentage_bps: 10, fixed_amount: 0, minimum_fee: 100})

    {:ok, fee} = Pricing.compute_fee(merchant.id, 100, "card", nil)

    assert fee.amount == 100
  end

  # ── activate_plan/2 ───────────────────────────────────────────────────────────

  test "activate_plan transitions draft to active" do
    plan = plan_fixture(%{created_by: "alice"})
    assert plan.status == "draft"

    {:ok, activated} = Pricing.activate_plan(plan.public_id, "bob")

    assert activated.status == "active"
    assert activated.activated_by == "bob"
    assert activated.activated_at != nil
  end

  test "activate_plan is idempotent when already active" do
    plan = active_plan_fixture()

    assert {:ok, %{status: "active"}} = Pricing.activate_plan(plan.public_id, "charlie")
  end

  test "activate_plan rejects SoD violation (same actor as creator)" do
    plan = plan_fixture(%{created_by: "alice"})

    assert {:error, %Ecto.Changeset{} = cs} = Pricing.activate_plan(plan.public_id, "alice")
    assert cs.errors[:activated_by] != nil
  end

  test "activate_plan returns :not_found for unknown plan" do
    assert {:error, :not_found} = Pricing.activate_plan("plan_nonexistent", "bob")
  end

  # ── assign_plan/2 ─────────────────────────────────────────────────────────────

  test "assign_plan accepts only active plans" do
    draft_plan = plan_fixture()
    merchant = Fixtures.approved_merchant_fixture()

    assert {:error, :plan_not_active} = Pricing.assign_plan(merchant.id, draft_plan.public_id)
  end

  test "assign_plan succeeds with an active plan" do
    active = active_plan_fixture()
    merchant = Fixtures.approved_merchant_fixture()

    assert {:ok, _plan} = Pricing.assign_plan(merchant.id, active.public_id)
  end

  # ── record_fee/5 ──────────────────────────────────────────────────────────────

  test "records a fee_record for a payment attempt" do
    {merchant, plan} = merchant_with_active_plan()
    _rule = rule_fixture(plan)
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
    {merchant, plan} = merchant_with_active_plan()
    _rule = rule_fixture(plan)
    {:ok, fee} = Pricing.compute_fee(merchant.id, 5_000, "card", nil)
    attempt_id = Ecto.UUID.generate()

    {:ok, first} =
      Pricing.record_fee("payment_attempt", attempt_id, merchant.id, fee, "simulation")

    {:ok, second} =
      Pricing.record_fee("payment_attempt", attempt_id, merchant.id, fee, "simulation")

    assert first.id == second.id
    assert Repo.aggregate(FeeRecord, :count) == 1
  end

  # ── reverse_fee/4 ─────────────────────────────────────────────────────────────

  defp fee_record_fixture(merchant, attempt_id, amount) do
    %FeeRecord{}
    |> FeeRecord.record_changeset(%{
      source_type: "payment_attempt",
      source_id: attempt_id,
      merchant_id: merchant.id,
      mode: "simulation",
      party: "platform",
      fee_kind: "psp_margin",
      amount: amount,
      currency: "GHS",
      computation: %{"gross_amount" => 10_000, "applied_fee" => amount}
    })
    |> Repo.insert!(on_conflict: :nothing, conflict_target: [:source_type, :source_id, :party])

    Repo.get_by!(FeeRecord,
      source_type: "payment_attempt",
      source_id: attempt_id,
      party: "platform"
    )
  end

  test "reverse_fee creates a reversal record for a full refund" do
    merchant = Fixtures.approved_merchant_fixture()
    attempt_id = Ecto.UUID.generate()
    refund_id = Ecto.UUID.generate()
    _original = fee_record_fixture(merchant, attempt_id, _fee = 170)

    {:ok, reversal} = Pricing.reverse_fee(attempt_id, merchant.id, refund_id, 10_000)

    assert %FeeRecord{} = reversal
    assert reversal.fee_kind == "psp_margin_reversal"
    assert reversal.amount == 170
    assert reversal.source_type == "refund"
    assert reversal.source_id == refund_id
  end

  test "reverse_fee computes proportional amount for partial refund" do
    merchant = Fixtures.approved_merchant_fixture()
    attempt_id = Ecto.UUID.generate()
    refund_id = Ecto.UUID.generate()
    _original = fee_record_fixture(merchant, attempt_id, _fee = 170)

    # Refund half the payment (5_000 of 10_000) → reverse half the fee (85 of 170)
    {:ok, reversal} = Pricing.reverse_fee(attempt_id, merchant.id, refund_id, 5_000)

    assert reversal.amount == 85
  end

  test "reverse_fee is idempotent — no double-reversal" do
    merchant = Fixtures.approved_merchant_fixture()
    attempt_id = Ecto.UUID.generate()
    refund_id = Ecto.UUID.generate()
    _original = fee_record_fixture(merchant, attempt_id, _fee = 170)

    {:ok, _} = Pricing.reverse_fee(attempt_id, merchant.id, refund_id, 10_000)
    {:ok, :already_reversed} = Pricing.reverse_fee(attempt_id, merchant.id, refund_id, 10_000)

    assert Repo.aggregate(FeeRecord |> where([f], f.fee_kind == "psp_margin_reversal"), :count) ==
             1
  end

  test "reverse_fee is non-fatal when no original fee exists" do
    merchant = Fixtures.approved_merchant_fixture()
    attempt_id = Ecto.UUID.generate()
    refund_id = Ecto.UUID.generate()

    assert {:ok, :no_fee_to_reverse} =
             Pricing.reverse_fee(attempt_id, merchant.id, refund_id, 5_000)
  end
end
