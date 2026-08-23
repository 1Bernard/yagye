defmodule YagyeCore.Customers.VelocityCheckerTest do
  use YagyeCore.DataCase, async: true

  alias YagyeCore.Customers.Schemas.VelocityLimit
  alias YagyeCore.Customers.VelocityChecker
  alias YagyeCore.Fixtures
  alias YagyeCore.Repo

  # ── Fixtures ─────────────────────────────────────────────────────────────────

  defp low_risk_merchant do
    merchant = Fixtures.approved_merchant_fixture()

    Repo.update_all(
      YagyeCore.Merchants.Schemas.Merchant |> where([m], m.id == ^merchant.id),
      set: [risk_rating: "low"]
    )

    Repo.get!(YagyeCore.Merchants.Schemas.Merchant, merchant.id)
  end

  defp high_risk_merchant do
    merchant = Fixtures.approved_merchant_fixture()

    Repo.update_all(
      YagyeCore.Merchants.Schemas.Merchant |> where([m], m.id == ^merchant.id),
      set: [risk_rating: "high"]
    )

    Repo.get!(YagyeCore.Merchants.Schemas.Merchant, merchant.id)
  end

  defp seed_limit(attrs) do
    %VelocityLimit{} |> VelocityLimit.create_changeset(attrs) |> Repo.insert!()
  end

  # ── check/5 ──────────────────────────────────────────────────────────────────

  test "passes when amount is under single txn limit (fallback defaults)" do
    merchant = low_risk_merchant()
    # Low risk default: max_single_txn = 5_000_000 pesewas (GHS 50,000)
    assert :ok = VelocityChecker.check(merchant.id, nil, 1_000, "card", "GHS")
  end

  test "fails single_txn_limit_exceeded when amount exceeds limit from DB row" do
    merchant = low_risk_merchant()

    seed_limit(%{
      entity_type: "merchant",
      risk_tier: "low",
      payment_method: "card",
      currency: "GHS",
      max_single_txn: 500,
      max_daily: nil,
      max_monthly: nil
    })

    assert {:error, :single_txn_limit_exceeded} =
             VelocityChecker.check(merchant.id, nil, 1_000, "card", "GHS")
  end

  test "passes when no velocity limit row exists (uses hardcoded defaults)" do
    merchant = low_risk_merchant()
    # No DB rows seeded — falls back to default_limits/0
    assert :ok = VelocityChecker.check(merchant.id, nil, 100, "mobile_money", "GHS")
  end

  test "high risk merchant has tighter single txn limit by default" do
    merchant = high_risk_merchant()
    # High risk default: max_single_txn = 200_000 pesewas (GHS 2,000)
    assert :ok = VelocityChecker.check(merchant.id, nil, 100_000, "card", "GHS")

    assert {:error, :single_txn_limit_exceeded} =
             VelocityChecker.check(merchant.id, nil, 300_000, "card", "GHS")
  end
end
