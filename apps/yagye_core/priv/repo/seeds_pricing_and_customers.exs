###############################################################################
# seeds_pricing_and_customers.exs
#
# Seeds a pricing plan, customers, settlement batches, and fee invoices
# for the demo merchant (Kofi Builds Ltd / MCH_DEMO_001).
# Safe to run multiple times — all inserts are idempotent.
###############################################################################

import Ecto.Query

alias YagyeCore.Repo
alias YagyeCore.Merchants.Schemas.Merchant
alias YagyeCore.Pricing.Schemas.{PricingPlan, PricingRule, PlatformFeeInvoice}
alias YagyeCore.Customers.Schemas.Customer
alias YagyeCore.Settlement.Schemas.SettlementBatch

IO.puts("\n=== Pricing, Customers & Settlement Batches Seed ===\n")

# ── Resolve demo merchant ──────────────────────────────────────────────────────

merchant = Repo.get_by!(Merchant, public_id: "MCH_DEMO_001")
merchant_id = merchant.id
IO.puts("Merchant: " <> merchant.legal_name <> " (" <> merchant.public_id <> ")")

# ── 1. Pricing plan ───────────────────────────────────────────────────────────

plan =
  case Repo.get_by(PricingPlan, name: "Standard GHS", version: 1) do
    %PricingPlan{} = existing ->
      IO.puts("Pricing plan: already exists (" <> existing.public_id <> ")")
      existing

    nil ->
      {:ok, p} =
        %PricingPlan{}
        |> Ecto.Changeset.change(%{
          public_id: "plan_" <> Uniq.UUID.uuid7(),
          name: "Standard GHS",
          version: 1,
          currency: "GHS",
          fee_mode: "deducted",
          monthly_fee: 0,
          effective_from: ~U[2026-01-01 00:00:00.000000Z],
          inserted_at: DateTime.utc_now()
        })
        |> Repo.insert()

      IO.puts("Pricing plan: created (" <> p.public_id <> ")")
      p
  end

# Assign plan to merchant if not already set
if is_nil(merchant.pricing_plan_id) do
  Repo.update_all(
    from(m in Merchant, where: m.id == ^merchant_id),
    set: [pricing_plan_id: plan.id]
  )
  IO.puts("Pricing plan: assigned to " <> merchant.legal_name)
end

# ── 2. Pricing rules ──────────────────────────────────────────────────────────

existing_rule_count = Repo.aggregate(from(r in PricingRule, where: r.plan_id == ^plan.id), :count)

if existing_rule_count > 0 do
  IO.puts("Pricing rules: " <> to_string(existing_rule_count) <> " already exist — skipping")
else
  rules_config = [
    # Default catch-all — any method
    %{method: nil,             provider_code: nil,         percentage_bps: 150, fixed_amount: 50,  minimum_fee: 50,  maximum_fee: 5000, specificity: 0},
    # MoMo — any provider
    %{method: "mobile_money",  provider_code: nil,         percentage_bps: 150, fixed_amount: 50,  minimum_fee: 50,  maximum_fee: 5000, specificity: 1},
    # MTN MoMo specifically
    %{method: "mobile_money",  provider_code: "mtn_momo_gh", percentage_bps: 175, fixed_amount: 50, minimum_fee: 50, maximum_fee: 5000, specificity: 3},
    # Bank transfer — flat fee
    %{method: "bank_transfer", provider_code: nil,         percentage_bps: 0,   fixed_amount: 200, minimum_fee: 200, maximum_fee: 200,  specificity: 1},
    # Card — higher MDR
    %{method: "card",          provider_code: nil,         percentage_bps: 290, fixed_amount: 0,   minimum_fee: 100, maximum_fee: nil,  specificity: 1},
  ]

  now = DateTime.utc_now()

  Enum.each(rules_config, fn cfg ->
    %PricingRule{}
    |> Ecto.Changeset.change(Map.merge(cfg, %{plan_id: plan.id, rounding: "half_up", inserted_at: now}))
    |> Repo.insert!(on_conflict: :nothing)
  end)

  IO.puts("Pricing rules: seeded " <> to_string(length(rules_config)) <> " rules")
end

# ── 3. Customers ──────────────────────────────────────────────────────────────

customer_count = Repo.aggregate(from(c in Customer, where: c.merchant_id == ^merchant_id), :count)

if customer_count >= 10 do
  IO.puts("Customers: " <> to_string(customer_count) <> " already exist — skipping")
else
  customers_data = [
    %{ref: "CUST-001", tier: "tier_2", verified_at: ~U[2026-06-01 09:00:00.000000Z]},
    %{ref: "CUST-002", tier: "tier_1", verified_at: nil},
    %{ref: "CUST-003", tier: "tier_2", verified_at: ~U[2026-07-12 14:30:00.000000Z]},
    %{ref: "CUST-004", tier: "tier_1", verified_at: nil},
    %{ref: "CUST-005", tier: "tier_2", verified_at: ~U[2026-05-20 11:00:00.000000Z]},
    %{ref: "CUST-006", tier: "tier_2", verified_at: ~U[2026-08-03 08:45:00.000000Z]},
    %{ref: "CUST-007", tier: "tier_1", verified_at: nil},
    %{ref: "CUST-008", tier: "tier_2", verified_at: ~U[2026-09-01 10:00:00.000000Z]},
    %{ref: "CUST-009", tier: "tier_1", verified_at: nil},
    %{ref: "CUST-010", tier: "tier_2", verified_at: ~U[2026-09-10 16:00:00.000000Z]},
  ]

  now = DateTime.utc_now()

  Enum.each(customers_data, fn c ->
    %Customer{}
    |> Ecto.Changeset.change(%{
      public_id:             "cus_" <> Uniq.UUID.uuid7(),
      merchant_id:           merchant_id,
      merchant_customer_ref: c.ref,
      kyc_tier:              c.tier,
      kyc_verified_at:       c.verified_at,
      inserted_at:           now,
      updated_at:            now
    })
    |> Repo.insert!(on_conflict: :nothing, conflict_target: [:merchant_id, :merchant_customer_ref])
  end)

  IO.puts("Customers: seeded 10")
end

# ── 4. Settlement batches ─────────────────────────────────────────────────────

alias YagyeCore.Providers.Schemas.Provider
provider = Repo.get_by!(Provider, code: "simulator")

batch_count = Repo.aggregate(from(b in SettlementBatch, where: b.merchant_id == ^merchant_id), :count)

if batch_count >= 3 do
  IO.puts("Settlement batches: " <> to_string(batch_count) <> " already exist — skipping")
else
  batches_data = [
    %{period_start: ~U[2026-06-01 00:00:00.000000Z], period_end: ~U[2026-06-30 23:59:59.000000Z], gross: 4_875_000, count: 312, state: "settled",  settled_at: ~U[2026-07-02 06:00:00.000000Z]},
    %{period_start: ~U[2026-07-01 00:00:00.000000Z], period_end: ~U[2026-07-31 23:59:59.000000Z], gross: 6_210_000, count: 401, state: "settled",  settled_at: ~U[2026-08-02 06:00:00.000000Z]},
    %{period_start: ~U[2026-08-01 00:00:00.000000Z], period_end: ~U[2026-08-31 23:59:59.000000Z], gross: 5_543_000, count: 358, state: "pending",  settled_at: nil},
  ]

  now = DateTime.utc_now()

  Enum.each(batches_data, fn b ->
    existing = Repo.one(
      from(sb in SettlementBatch,
        where: sb.merchant_id == ^merchant_id and sb.period_start == ^b.period_start
      )
    )

    if is_nil(existing) do
      %SettlementBatch{}
      |> Ecto.Changeset.change(%{
        id:           Ecto.UUID.generate(),
        merchant_id:  merchant_id,
        currency:     "GHS",
        mode:         "simulation",
        provider_id:  provider.id,
        period_start: b.period_start,
        period_end:   b.period_end,
        payment_count: b.count,
        gross_amount:  b.gross,
        state:         b.state,
        settled_at:    b.settled_at,
        inserted_at:   now
      })
      |> Repo.insert!(on_conflict: :nothing)
    end
  end)

  IO.puts("Settlement batches: seeded 3")
end

# ── 5. Platform fee invoices ──────────────────────────────────────────────────

invoice_count = Repo.aggregate(from(i in PlatformFeeInvoice, where: i.merchant_id == ^merchant_id), :count)

if invoice_count >= 2 do
  IO.puts("Fee invoices: " <> to_string(invoice_count) <> " already exist — skipping")
else
  invoices_data = [
    %{period_start: ~D[2026-06-01], period_end: ~D[2026-06-30], total: 73_125, state: "collected", collected_at: ~U[2026-07-03 09:00:00.000000Z], due_at: ~U[2026-07-05 00:00:00.000000Z]},
    %{period_start: ~D[2026-07-01], period_end: ~D[2026-07-31], total: 93_150, state: "collected", collected_at: ~U[2026-08-04 09:00:00.000000Z], due_at: ~U[2026-08-05 00:00:00.000000Z]},
    %{period_start: ~D[2026-08-01], period_end: ~D[2026-08-31], total: 83_145, state: "issued",    collected_at: nil,                            due_at: ~U[2026-09-10 00:00:00.000000Z]},
  ]

  now = DateTime.utc_now()

  Enum.each(invoices_data, fn inv ->
    %PlatformFeeInvoice{}
    |> Ecto.Changeset.change(%{
      public_id:         "pfi_" <> Uniq.UUID.uuid7(),
      merchant_id:       merchant_id,
      mode:              "simulation",
      period_start:      inv.period_start,
      period_end:        inv.period_end,
      currency:          "GHS",
      total_amount:      inv.total,
      collection_method: "cross_net",
      state:             inv.state,
      due_at:            inv.due_at,
      collected_at:      inv.collected_at,
      inserted_at:       now,
      updated_at:        now
    })
    |> Repo.insert!(on_conflict: :nothing, conflict_target: [:merchant_id, :mode, :period_start, :period_end])
  end)

  IO.puts("Fee invoices: seeded 3")
end

IO.puts("\n=== Done ===\n")
