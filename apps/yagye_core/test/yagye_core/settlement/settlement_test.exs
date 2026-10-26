defmodule YagyeCore.Settlement.SettlementTest do
  use YagyeCore.DataCase, async: true

  alias YagyeCore.Fixtures
  alias YagyeCore.Outbox.Schemas.OutboxMessage
  alias YagyeCore.Payments.Schemas.Payment
  alias YagyeCore.Payments.Schemas.PaymentAttempt
  alias YagyeCore.Providers.Schemas.Provider
  alias YagyeCore.Repo
  alias YagyeCore.Settlement
  alias YagyeCore.Settlement.Schemas.SettlementBatch

  # Creates a payment in `succeeded` state with a succeeded attempt linked to provider.
  # Bypasses the full payment flow (no ledger/events) so tests remain isolated.
  defp succeeded_payment_with_attempt(merchant, provider, attrs \\ %{}) do
    payment =
      Fixtures.payment_fixture(
        merchant,
        Map.merge(%{currency: "GHS", mode: "simulation"}, attrs)
      )

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
    payment
  end

  defp provider_fixture(code \\ "prov_#{System.unique_integer([:positive])}") do
    Repo.insert!(
      Provider.changeset(%Provider{}, %{
        code: code,
        display_name: "Provider #{code}",
        adapter_module: "YagyeCore.Payments.Adapters.SimulatorAdapter",
        active: true
      })
    )
  end

  describe "create_batch/4" do
    setup do
      merchant = Fixtures.merchant_fixture()
      provider = Fixtures.simulator_provider_fixture()
      %{merchant: merchant, provider: provider}
    end

    test "returns :no_payments when no unsettled succeeded payments exist",
         %{merchant: merchant, provider: provider} do
      assert {:error, :no_payments} =
               Settlement.create_batch(merchant.id, provider.id, "GHS", "simulation")
    end

    test "creates a pending batch sweeping all unsettled succeeded payments",
         %{merchant: merchant, provider: provider} do
      p1 = succeeded_payment_with_attempt(merchant, provider)
      p2 = succeeded_payment_with_attempt(merchant, provider)

      assert {:ok, batch} = Settlement.create_batch(merchant.id, provider.id, "GHS", "simulation")

      assert batch.state == "pending"
      assert batch.merchant_id == merchant.id
      assert batch.provider_id == provider.id
      assert batch.currency == "GHS"
      assert batch.mode == "simulation"
      assert batch.payment_count == 2
      assert batch.gross_amount == p1.amount + p2.amount
    end

    test "emits a settlement.batch.created outbox event",
         %{merchant: merchant, provider: provider} do
      succeeded_payment_with_attempt(merchant, provider)

      {:ok, batch} = Settlement.create_batch(merchant.id, provider.id, "GHS", "simulation")

      msg =
        Repo.get_by(OutboxMessage,
          aggregate_type: "settlementbatch",
          aggregate_id: batch.id,
          event_type: "settlement.batch.created"
        )

      assert msg != nil
      assert msg.mode == "simulation"
    end

    test "sets period_start to the earliest payment's inserted_at",
         %{merchant: merchant, provider: provider} do
      p1 = succeeded_payment_with_attempt(merchant, provider)
      _p2 = succeeded_payment_with_attempt(merchant, provider)

      {:ok, batch} = Settlement.create_batch(merchant.id, provider.id, "GHS", "simulation")

      assert DateTime.compare(batch.period_start, p1.inserted_at) in [:lt, :eq]
    end

    test "only sweeps payments matching the given currency",
         %{merchant: merchant, provider: provider} do
      _ghs = succeeded_payment_with_attempt(merchant, provider, %{currency: "GHS"})
      _usd = succeeded_payment_with_attempt(merchant, provider, %{currency: "USD"})

      {:ok, batch} = Settlement.create_batch(merchant.id, provider.id, "GHS", "simulation")

      assert batch.payment_count == 1
    end

    test "only sweeps payments processed by the given provider",
         %{merchant: merchant, provider: provider} do
      other = provider_fixture()
      succeeded_payment_with_attempt(merchant, provider)
      succeeded_payment_with_attempt(merchant, other)

      {:ok, batch} = Settlement.create_batch(merchant.id, provider.id, "GHS", "simulation")

      assert batch.payment_count == 1
    end

    test "ignores payments already assigned to a batch",
         %{merchant: merchant, provider: provider} do
      succeeded_payment_with_attempt(merchant, provider)
      {:ok, batch} = Settlement.create_batch(merchant.id, provider.id, "GHS", "simulation")
      {:ok, batch} = Settlement.transition_batch(batch, "processing")
      {:ok, _} = Settlement.transition_batch(batch, "settled")

      # No new payments — the stamped one should be excluded
      assert {:error, :no_payments} =
               Settlement.create_batch(merchant.id, provider.id, "GHS", "simulation")
    end

    test "ignores payments that have not reached succeeded state",
         %{merchant: merchant, provider: provider} do
      Fixtures.payment_fixture(merchant, %{currency: "GHS", mode: "simulation"})

      assert {:error, :no_payments} =
               Settlement.create_batch(merchant.id, provider.id, "GHS", "simulation")
    end

    test "returns :batch_already_open when a pending batch exists",
         %{merchant: merchant, provider: provider} do
      succeeded_payment_with_attempt(merchant, provider)
      {:ok, _} = Settlement.create_batch(merchant.id, provider.id, "GHS", "simulation")

      succeeded_payment_with_attempt(merchant, provider)

      assert {:error, :batch_already_open} =
               Settlement.create_batch(merchant.id, provider.id, "GHS", "simulation")
    end

    test "returns :batch_already_open when a processing batch exists",
         %{merchant: merchant, provider: provider} do
      succeeded_payment_with_attempt(merchant, provider)
      {:ok, batch} = Settlement.create_batch(merchant.id, provider.id, "GHS", "simulation")
      {:ok, _} = Settlement.transition_batch(batch, "processing")

      succeeded_payment_with_attempt(merchant, provider)

      assert {:error, :batch_already_open} =
               Settlement.create_batch(merchant.id, provider.id, "GHS", "simulation")
    end

    test "allows a new batch after the previous one is settled",
         %{merchant: merchant, provider: provider} do
      succeeded_payment_with_attempt(merchant, provider)
      {:ok, batch} = Settlement.create_batch(merchant.id, provider.id, "GHS", "simulation")
      {:ok, batch} = Settlement.transition_batch(batch, "processing")
      {:ok, _} = Settlement.transition_batch(batch, "settled")

      succeeded_payment_with_attempt(merchant, provider)

      assert {:ok, _new_batch} =
               Settlement.create_batch(merchant.id, provider.id, "GHS", "simulation")
    end

    test "does not double-count a payment with multiple succeeded attempts from same provider",
         %{merchant: merchant, provider: provider} do
      payment = succeeded_payment_with_attempt(merchant, provider)

      # Insert a second succeeded attempt for the same payment+provider
      Repo.insert!(
        PaymentAttempt.changeset(%PaymentAttempt{}, %{
          payment_id: payment.id,
          provider_id: provider.id,
          attempt_number: 2,
          state: "succeeded",
          provider_reference: "chg_dup_#{System.unique_integer([:positive])}",
          idempotency_token: Uniq.UUID.uuid7()
        })
      )

      {:ok, batch} = Settlement.create_batch(merchant.id, provider.id, "GHS", "simulation")

      assert batch.payment_count == 1
    end
  end

  describe "create_batch/4 — T+N delay" do
    setup do
      merchant = Fixtures.merchant_fixture()
      provider = Fixtures.simulator_provider_fixture()
      %{merchant: merchant, provider: provider}
    end

    test "delay_days=0 (default) sweeps all payments regardless of age",
         %{merchant: merchant, provider: provider} do
      payment = succeeded_payment_with_attempt(merchant, provider)
      # Payment is recent (just inserted). 0 = no cutoff filter.
      Settlement.upsert_settlement_controls(merchant.id, %{
        settlement_delay_days: 0,
        updated_by: "test"
      })

      assert {:ok, batch} = Settlement.create_batch(merchant.id, provider.id, "GHS", "simulation")
      assert batch.gross_amount == payment.amount
    end

    test "delay_days=1 excludes a payment inserted today",
         %{merchant: merchant, provider: provider} do
      succeeded_payment_with_attempt(merchant, provider)
      # Controls: T+1 — only payments at least 1 business day old are eligible.
      Settlement.upsert_settlement_controls(merchant.id, %{
        settlement_delay_days: 1,
        minimum_payout_pesewas: 0,
        updated_by: "test"
      })

      # Payment inserted_at is "now" — still within today, so cutoff excludes it.
      assert {:error, :no_payments} =
               Settlement.create_batch(merchant.id, provider.id, "GHS", "simulation")
    end

    test "delay_days=1 includes a payment inserted 3 days ago",
         %{merchant: merchant, provider: provider} do
      payment = succeeded_payment_with_attempt(merchant, provider)

      # Back-date the payment 3 days — well past any T+1 cutoff.
      three_days_ago = DateTime.add(DateTime.utc_now(), -3 * 24 * 3600, :second)

      Ecto.Changeset.change(payment, inserted_at: three_days_ago)
      |> Repo.update!()

      Settlement.upsert_settlement_controls(merchant.id, %{
        settlement_delay_days: 1,
        minimum_payout_pesewas: 0,
        updated_by: "test"
      })

      assert {:ok, batch} = Settlement.create_batch(merchant.id, provider.id, "GHS", "simulation")
      assert batch.gross_amount == payment.amount
    end
  end

  describe "create_batch/4 — minimum payout" do
    setup do
      merchant = Fixtures.merchant_fixture()
      provider = Fixtures.simulator_provider_fixture()
      %{merchant: merchant, provider: provider}
    end

    test "returns :below_minimum when eligible gross < minimum_payout_pesewas",
         %{merchant: merchant, provider: provider} do
      # Payment amount 1000 pesewas; minimum is 5000.
      succeeded_payment_with_attempt(merchant, provider, %{amount: 1_000})

      Settlement.upsert_settlement_controls(merchant.id, %{
        minimum_payout_pesewas: 5_000,
        updated_by: "test"
      })

      assert {:error, :below_minimum} =
               Settlement.create_batch(merchant.id, provider.id, "GHS", "simulation")
    end

    test "creates batch when eligible gross >= minimum_payout_pesewas",
         %{merchant: merchant, provider: provider} do
      succeeded_payment_with_attempt(merchant, provider, %{amount: 10_000})

      Settlement.upsert_settlement_controls(merchant.id, %{
        minimum_payout_pesewas: 5_000,
        updated_by: "test"
      })

      assert {:ok, batch} = Settlement.create_batch(merchant.id, provider.id, "GHS", "simulation")
      assert batch.gross_amount == 10_000
    end

    test "skips minimum check when minimum_payout_pesewas is 0",
         %{merchant: merchant, provider: provider} do
      succeeded_payment_with_attempt(merchant, provider, %{amount: 100})

      Settlement.upsert_settlement_controls(merchant.id, %{
        minimum_payout_pesewas: 0,
        updated_by: "test"
      })

      assert {:ok, _batch} =
               Settlement.create_batch(merchant.id, provider.id, "GHS", "simulation")
    end
  end

  describe "get_batch/1" do
    test "returns the batch when found" do
      merchant = Fixtures.merchant_fixture()
      provider = Fixtures.simulator_provider_fixture()
      succeeded_payment_with_attempt(merchant, provider)
      {:ok, batch} = Settlement.create_batch(merchant.id, provider.id, "GHS", "simulation")

      assert %SettlementBatch{id: id} = Settlement.get_batch(batch.id)
      assert id == batch.id
    end

    test "returns nil when not found" do
      assert nil == Settlement.get_batch(Uniq.UUID.uuid7())
    end
  end

  describe "transition_batch/2" do
    test "transitions a batch to a valid state" do
      merchant = Fixtures.merchant_fixture()
      provider = Fixtures.simulator_provider_fixture()
      succeeded_payment_with_attempt(merchant, provider)
      {:ok, batch} = Settlement.create_batch(merchant.id, provider.id, "GHS", "simulation")

      assert {:ok, updated} = Settlement.transition_batch(batch, "processing")
      assert updated.state == "processing"
    end

    test "returns :invalid_state for unknown states" do
      batch = %SettlementBatch{state: "pending"}
      assert {:error, :invalid_state} = Settlement.transition_batch(batch, "unknown")
    end
  end
end
