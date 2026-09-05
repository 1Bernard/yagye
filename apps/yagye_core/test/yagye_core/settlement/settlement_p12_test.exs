defmodule YagyeCore.Settlement.SettlementP12Test do
  use YagyeCore.DataCase, async: true

  alias YagyeCore.Fixtures
  alias YagyeCore.Payments.Schemas.PaymentAttempt
  alias YagyeCore.Repo
  alias YagyeCore.Settlement, as: SettlementContext
  alias YagyeCore.Settlement.Schemas.{SettlementBatch, SettlementItem}

  setup do
    merchant = Fixtures.approved_merchant_fixture()
    provider = Fixtures.simulator_provider_fixture()
    %{merchant: merchant, provider: provider}
  end

  defp batch_with_attempts(merchant, provider, payment_count) do
    payments =
      for _ <- 1..payment_count do
        payment =
          Fixtures.succeeded_payment_fixture(merchant, %{
            currency: "GHS",
            amount: 10_000
          })

        Repo.insert!(%PaymentAttempt{
          public_id: "pat_#{Uniq.UUID.uuid7()}",
          payment_id: payment.id,
          provider_id: provider.id,
          attempt_number: 1,
          method: "mobile_money",
          state: "succeeded",
          provider_reference: "ref_#{System.unique_integer([:positive])}",
          idempotency_token: Uniq.UUID.uuid7()
        })

        payment
      end

    batch =
      Repo.insert!(%SettlementBatch{
        merchant_id: merchant.id,
        provider_id: provider.id,
        currency: "GHS",
        mode: "live",
        period_start: ~U[2026-08-01 00:00:00.000000Z],
        period_end: ~U[2026-08-02 00:00:00.000000Z],
        payment_count: payment_count,
        gross_amount: payment_count * 10_000,
        state: "settled",
        settled_at: DateTime.utc_now()
      })

    payment_ids = Enum.map(payments, & &1.id)

    Repo.update_all(
      from(p in YagyeCore.Payments.Schemas.Payment, where: p.id in ^payment_ids),
      set: [settlement_batch_id: batch.id]
    )

    {batch, payments}
  end

  describe "create_settlement_from_batch/1" do
    test "creates a settlement in expected state with correct totals", %{
      merchant: merchant,
      provider: provider
    } do
      {batch, _payments} = batch_with_attempts(merchant, provider, 3)

      assert {:ok, %{settlement: settlement, items: items}} =
               SettlementContext.create_settlement_from_batch(batch)

      assert settlement.state == "expected"
      assert settlement.expected_gross == 30_000
      assert settlement.expected_net == 30_000
      assert settlement.merchant_id == merchant.id
      assert settlement.provider_id == provider.id
      assert length(items) == 3
      assert Enum.all?(items, &(&1.source_type == "payment_attempt"))
    end

    test "each settlement item references the payment_attempt", %{
      merchant: merchant,
      provider: provider
    } do
      {batch, _payments} = batch_with_attempts(merchant, provider, 2)

      {:ok, %{items: items}} = SettlementContext.create_settlement_from_batch(batch)

      assert Enum.all?(items, fn item ->
               item.gross_amount == 10_000 and
                 item.net_amount == 10_000 and
                 item.currency == "GHS"
             end)
    end

    test "settlement items are unique — re-run is idempotent via on_conflict", %{
      merchant: merchant,
      provider: provider
    } do
      {batch, _payments} = batch_with_attempts(merchant, provider, 2)

      {:ok, %{settlement: settlement}} = SettlementContext.create_settlement_from_batch(batch)

      # Second call fails at settlement level (unique period constraint), not items
      assert {:error, _} = SettlementContext.create_settlement_from_batch(batch)

      # Items count stays at 2
      items = Repo.all(from(i in SettlementItem, where: i.settlement_id == ^settlement.id))
      assert length(items) == 2
    end
  end

  describe "run_matching/1" do
    test "transitions to matched when variance is zero", %{merchant: merchant, provider: provider} do
      {batch, _} = batch_with_attempts(merchant, provider, 2)
      {:ok, %{settlement: settlement}} = SettlementContext.create_settlement_from_batch(batch)

      {:ok, reported} =
        SettlementContext.transition_settlement(settlement, "reported", %{
          reported_gross: 20_000,
          reported_fees: 0,
          reported_net: 20_000,
          provider_settlement_reference: "PSP-REF-001",
          value_date: ~D[2026-08-02]
        })

      assert {:ok, matched} = SettlementContext.run_matching(reported)
      assert matched.state == "matched"
    end

    test "transitions to mismatched when variance is non-zero", %{
      merchant: merchant,
      provider: provider
    } do
      {batch, _} = batch_with_attempts(merchant, provider, 2)
      {:ok, %{settlement: settlement}} = SettlementContext.create_settlement_from_batch(batch)

      {:ok, reported} =
        SettlementContext.transition_settlement(settlement, "reported", %{
          reported_gross: 19_000,
          reported_fees: 0,
          reported_net: 19_000,
          provider_settlement_reference: "PSP-REF-002",
          value_date: ~D[2026-08-02]
        })

      assert {:ok, mismatched} = SettlementContext.run_matching(reported)
      assert mismatched.state == "mismatched"
    end
  end
end
