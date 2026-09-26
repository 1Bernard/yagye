defmodule YagyeCore.Settlement.SettlementFeeTest do
  use YagyeCore.DataCase, async: true

  alias YagyeCore.Fixtures
  alias YagyeCore.Payments.Schemas.{Payment, PaymentAttempt}
  alias YagyeCore.Pricing.Schemas.FeeRecord
  alias YagyeCore.Repo
  alias YagyeCore.Settlement

  defp setup_payment_with_attempt(merchant, provider, amount \\ 10_000) do
    payment = Fixtures.payment_fixture(merchant, %{currency: "GHS", amount: amount})

    attempt =
      Repo.insert!(
        PaymentAttempt.changeset(%PaymentAttempt{}, %{
          payment_id: payment.id,
          provider_id: provider.id,
          attempt_number: 1,
          state: "succeeded",
          provider_reference: "chg_#{System.unique_integer([:positive])}",
          idempotency_token: Uniq.UUID.uuid7()
        })
      )

    {:ok, payment} = payment |> Payment.transition_changeset("succeeded") |> Repo.update()
    {:ok, batch} = Settlement.create_batch(merchant.id, provider.id, "GHS", "simulation")
    {Repo.reload!(batch), payment, attempt}
  end

  defp insert_fee(attempt, merchant, amount, party) do
    Repo.insert!(
      FeeRecord.record_changeset(%FeeRecord{}, %{
        source_type: "payment_attempt",
        source_id: attempt.id,
        merchant_id: merchant.id,
        mode: "simulation",
        party: party,
        fee_kind: "psp_margin",
        amount: amount,
        currency: "GHS",
        computation: %{"basis_points" => 150}
      })
    )
  end

  describe "compute_batch_fee_totals/1" do
    test "sums platform party fees and computes correct net" do
      merchant = Fixtures.merchant_fixture()
      provider = Fixtures.simulator_provider_fixture()
      {batch, _payment, attempt} = setup_payment_with_attempt(merchant, provider)
      insert_fee(attempt, merchant, 150, "platform")

      assert {:ok, totals} = Settlement.compute_batch_fee_totals(batch)
      assert totals.expected_platform_fees == 150
      assert totals.expected_provider_fees == 0
      assert totals.expected_net == 10_000 - 150
    end

    test "does not count provider party fees as platform fees" do
      merchant = Fixtures.merchant_fixture()
      provider = Fixtures.simulator_provider_fixture()
      {batch, _payment, attempt} = setup_payment_with_attempt(merchant, provider)
      insert_fee(attempt, merchant, 200, "provider")

      assert {:ok, totals} = Settlement.compute_batch_fee_totals(batch)
      assert totals.expected_platform_fees == 0
      assert totals.expected_provider_fees == 200
      assert totals.expected_net == 10_000 - 200
    end

    test "returns zero fees when no fee records exist" do
      merchant = Fixtures.merchant_fixture()
      provider = Fixtures.simulator_provider_fixture()
      {batch, payment, _attempt} = setup_payment_with_attempt(merchant, provider)

      assert {:ok, totals} = Settlement.compute_batch_fee_totals(batch)
      assert totals.expected_platform_fees == 0
      assert totals.expected_net == payment.amount
    end

    test "sums fees across multiple payments in the batch" do
      merchant = Fixtures.merchant_fixture()
      provider = Fixtures.simulator_provider_fixture()

      p1 = Fixtures.payment_fixture(merchant, %{currency: "GHS", amount: 10_000})

      a1 =
        Repo.insert!(
          PaymentAttempt.changeset(%PaymentAttempt{}, %{
            payment_id: p1.id,
            provider_id: provider.id,
            attempt_number: 1,
            state: "succeeded",
            provider_reference: "chg_#{System.unique_integer([:positive])}",
            idempotency_token: Uniq.UUID.uuid7()
          })
        )

      {:ok, _} = p1 |> Payment.transition_changeset("succeeded") |> Repo.update()

      p2 = Fixtures.payment_fixture(merchant, %{currency: "GHS", amount: 5_000})

      a2 =
        Repo.insert!(
          PaymentAttempt.changeset(%PaymentAttempt{}, %{
            payment_id: p2.id,
            provider_id: provider.id,
            attempt_number: 1,
            state: "succeeded",
            provider_reference: "chg_#{System.unique_integer([:positive])}",
            idempotency_token: Uniq.UUID.uuid7()
          })
        )

      {:ok, _} = p2 |> Payment.transition_changeset("succeeded") |> Repo.update()

      {:ok, batch} = Settlement.create_batch(merchant.id, provider.id, "GHS", "simulation")

      insert_fee(a1, merchant, 150, "platform")
      insert_fee(a2, merchant, 75, "platform")

      assert {:ok, totals} = Settlement.compute_batch_fee_totals(batch)
      assert totals.expected_platform_fees == 225
      assert totals.expected_gross == 15_000
      assert totals.expected_net == 15_000 - 225
    end
  end

  describe "create_settlement_from_batch/1 — per-item fees" do
    test "populates platform_fee and net_amount per item from fee_records" do
      merchant = Fixtures.merchant_fixture()
      provider = Fixtures.simulator_provider_fixture()
      {batch, payment, attempt} = setup_payment_with_attempt(merchant, provider)
      insert_fee(attempt, merchant, 150, "platform")

      {:ok, _} = Settlement.transition_batch(batch, "processing")
      {:ok, settled} = Settlement.transition_batch(Repo.reload!(batch), "settled")

      assert {:ok, %{items: [item]}} = Settlement.create_settlement_from_batch(settled)
      assert item.platform_fee == 150
      assert item.net_amount == payment.amount - 150
      assert item.gross_amount == payment.amount
    end

    test "sets platform_fee to 0 and net_amount equals gross when no fees" do
      merchant = Fixtures.merchant_fixture()
      provider = Fixtures.simulator_provider_fixture()
      {batch, payment, _attempt} = setup_payment_with_attempt(merchant, provider, 5_000)

      {:ok, _} = Settlement.transition_batch(batch, "processing")
      {:ok, settled} = Settlement.transition_batch(Repo.reload!(batch), "settled")

      assert {:ok, %{items: [item]}} = Settlement.create_settlement_from_batch(settled)
      assert item.platform_fee == 0
      assert item.net_amount == payment.amount
    end
  end
end
