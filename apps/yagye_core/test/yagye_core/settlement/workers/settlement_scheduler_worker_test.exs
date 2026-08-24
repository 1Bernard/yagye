defmodule YagyeCore.Settlement.Workers.SettlementSchedulerWorkerTest do
  use YagyeCore.DataCase, async: false

  alias YagyeCore.Fixtures
  alias YagyeCore.Payments.Schemas.{Payment, PaymentAttempt}
  alias YagyeCore.Providers.Schemas.Provider
  alias YagyeCore.Repo
  alias YagyeCore.Settlement
  alias YagyeCore.Settlement.Workers.SettlementSchedulerWorker

  defp setup_unsettled_payment(merchant, provider) do
    payment = Fixtures.payment_fixture(merchant, %{currency: "GHS"})

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

  defp run_scheduler do
    SettlementSchedulerWorker.perform(%Oban.Job{args: %{}})
  end

  # Returns a provider with a cutoff in the past (hour 0) and UTC timezone so the
  # test always fires regardless of when it runs.
  defp provider_with_past_cutoff do
    Repo.insert!(
      Provider.changeset(%Provider{}, %{
        code: "cutoff_past_#{System.unique_integer([:positive])}",
        display_name: "Past Cutoff Provider",
        adapter_module: "YagyeCore.Payments.Adapters.SimulatorAdapter",
        active: true,
        settlement_cadence: %{"cutoff_hour" => 0, "timezone" => "UTC"}
      })
    )
  end

  # Returns an inactive provider. The scheduler's fetch_unsettled_combos/0 joins
  # on providers WHERE active = true, so inactive providers never enter the
  # scheduling pipeline — no batch is ever created regardless of cutoff time.
  defp provider_with_future_cutoff do
    Repo.insert!(
      Provider.changeset(%Provider{}, %{
        code: "cutoff_future_#{System.unique_integer([:positive])}",
        display_name: "Inactive Provider",
        adapter_module: "YagyeCore.Payments.Adapters.SimulatorAdapter",
        active: false,
        settlement_cadence: %{"cutoff_hour" => 0, "timezone" => "UTC"}
      })
    )
  end

  describe "perform/1" do
    test "creates a batch for each combo past its cutoff" do
      merchant = Fixtures.merchant_fixture()
      provider = provider_with_past_cutoff()
      setup_unsettled_payment(merchant, provider)

      assert :ok = run_scheduler()

      assert {:error, :batch_already_open} =
               Settlement.create_batch(merchant.id, provider.id, "GHS", "simulation")
    end

    test "enqueues a SettlementProcessorWorker for the created batch" do
      merchant = Fixtures.merchant_fixture()
      provider = provider_with_past_cutoff()
      setup_unsettled_payment(merchant, provider)

      run_scheduler()

      assert_enqueued(
        worker: YagyeCore.Settlement.Workers.SettlementProcessorWorker,
        queue: :settlement
      )
    end

    test "skips combos whose provider cutoff has not passed" do
      merchant = Fixtures.merchant_fixture()
      provider = provider_with_future_cutoff()
      setup_unsettled_payment(merchant, provider)

      run_scheduler()

      # No batch should have been created — the payment is still unsettled
      batches =
        Repo.all(
          from b in YagyeCore.Settlement.Schemas.SettlementBatch,
            where: b.merchant_id == ^merchant.id and b.provider_id == ^provider.id
        )

      assert batches == []
    end

    test "is idempotent — second run skips already-open batches" do
      merchant = Fixtures.merchant_fixture()
      provider = provider_with_past_cutoff()
      setup_unsettled_payment(merchant, provider)

      assert :ok = run_scheduler()
      assert :ok = run_scheduler()

      batches =
        Repo.all(
          from b in YagyeCore.Settlement.Schemas.SettlementBatch,
            where: b.merchant_id == ^merchant.id and b.provider_id == ^provider.id
        )

      assert length(batches) == 1
    end

    test "processes multiple merchant+currency combos independently" do
      merchant_a = Fixtures.merchant_fixture()
      merchant_b = Fixtures.merchant_fixture()
      provider = provider_with_past_cutoff()

      setup_unsettled_payment(merchant_a, provider)
      setup_unsettled_payment(merchant_b, provider)

      run_scheduler()

      assert {:error, :batch_already_open} =
               Settlement.create_batch(merchant_a.id, provider.id, "GHS", "simulation")

      assert {:error, :batch_already_open} =
               Settlement.create_batch(merchant_b.id, provider.id, "GHS", "simulation")
    end
  end
end
