defmodule YagyeCore.Settlement.Workers.BankDispatchWorkerTest do
  use YagyeCore.DataCase, async: true

  alias YagyeCore.Fixtures
  alias YagyeCore.Ledger
  alias YagyeCore.Ledger.Schemas.Entry
  alias YagyeCore.Payments.Schemas.{Payment, PaymentAttempt}
  alias YagyeCore.Repo
  alias YagyeCore.Settlement
  alias YagyeCore.Settlement.Workers.BankDispatchWorker
  alias YagyeCore.Settlement.Workers.SettlementProcessorWorker

  # ── Helpers ───────────────────────────────────────────────────────────────────

  defp batch_with_payment(merchant, provider) do
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
    {:ok, batch} = Settlement.create_batch(merchant.id, provider.id, "GHS", "simulation")
    {Repo.reload!(batch), payment}
  end

  defp settled_batch(merchant, provider) do
    {batch, _} = batch_with_payment(merchant, provider)

    # SettlementProcessorWorker enqueues BankDispatchWorker but does NOT call the
    # disbursement API. No HTTP stub needed here.
    {:ok, settled} =
      SettlementProcessorWorker.perform(%Oban.Job{
        args: %{"settlement_batch_id" => batch.id}
      })

    Repo.reload!(settled)
  end

  defp run_worker(batch_id) do
    BankDispatchWorker.perform(%Oban.Job{args: %{"batch_id" => batch_id}})
  end

  defp stub_disbursement_success do
    ref = "DISB_#{System.unique_integer([:positive])}"

    Req.Test.stub(:simulator_http, fn conn ->
      conn
      |> Plug.Conn.put_status(201)
      |> Req.Test.json(%{
        "disbursement_ref" => ref,
        "state" => "PAID",
        "amount_minor" => 10_000,
        "currency" => "GHS",
        "destination_type" => "BANK",
        "destination_ref" => "merchant_test",
        "paid_at" => DateTime.to_iso8601(DateTime.utc_now())
      })
    end)

    ref
  end

  defp stub_disbursement_error(status) do
    Req.Test.stub(:simulator_http, fn conn ->
      conn
      |> Plug.Conn.put_status(status)
      |> Req.Test.json(%{"error" => "server_error"})
    end)
  end

  # ── Tests ─────────────────────────────────────────────────────────────────────

  describe "dispatch" do
    setup do
      merchant = Fixtures.merchant_fixture()
      provider = Fixtures.simulator_provider_fixture()
      _cred = Fixtures.simulator_credential_fixture(provider)
      %{merchant: merchant, provider: provider}
    end

    test "updates batch with bank_dispatch_ref and bank_dispatched_at", %{
      merchant: merchant,
      provider: provider
    } do
      batch = settled_batch(merchant, provider)
      disbursement_ref = stub_disbursement_success()

      assert :ok = run_worker(batch.id)

      updated = Repo.reload!(batch)
      assert updated.bank_dispatch_ref == disbursement_ref
      assert %DateTime{} = updated.bank_dispatched_at
    end

    test "posts batch_dispatched ledger entry", %{merchant: merchant, provider: provider} do
      batch = settled_batch(merchant, provider)
      stub_disbursement_success()

      run_worker(batch.id)

      entry =
        Repo.get_by(Entry,
          source_type: "settlement_batch",
          source_id: batch.id,
          entry_type: "batch_dispatched"
        )

      assert entry != nil
    end

    test "ledger closes settlement_approved to zero after dispatch", %{
      merchant: merchant,
      provider: provider
    } do
      batch = settled_batch(merchant, provider)
      stub_disbursement_success()

      run_worker(batch.id)

      {:ok, approved_account} =
        Ledger.get_account(
          "settlement_approved:#{batch.merchant_id}:#{batch.currency}:#{batch.mode}"
        )

      {:ok, approved_balance} = Ledger.get_balance(approved_account.id)

      # batch_approved credits settlement_approved; batch_dispatched debits it → net 0.
      assert approved_balance == 0
    end
  end

  describe "idempotency" do
    setup do
      merchant = Fixtures.merchant_fixture()
      provider = Fixtures.simulator_provider_fixture()
      _cred = Fixtures.simulator_credential_fixture(provider)
      %{merchant: merchant, provider: provider}
    end

    test "does not re-dispatch if bank_dispatch_ref already set", %{
      merchant: merchant,
      provider: provider
    } do
      batch = settled_batch(merchant, provider)
      stub_disbursement_success()

      # First dispatch
      assert :ok = run_worker(batch.id)
      first_ref = Repo.reload!(batch).bank_dispatch_ref

      # Second call — stub would give a different ref but worker must exit early
      stub_disbursement_success()
      assert :ok = run_worker(batch.id)

      assert Repo.reload!(batch).bank_dispatch_ref == first_ref
    end
  end

  describe "error handling" do
    setup do
      merchant = Fixtures.merchant_fixture()
      provider = Fixtures.simulator_provider_fixture()
      _cred = Fixtures.simulator_credential_fixture(provider)
      %{merchant: merchant, provider: provider}
    end

    test "returns error tuple when disbursement API fails", %{
      merchant: merchant,
      provider: provider
    } do
      batch = settled_batch(merchant, provider)
      stub_disbursement_error(500)

      assert {:error, {:http_error, 500}} = run_worker(batch.id)

      # batch is unchanged
      updated = Repo.reload!(batch)
      assert updated.bank_dispatch_ref == nil
    end
  end

  describe "SettlementProcessorWorker integration" do
    test "enqueues BankDispatchWorker job when batch settles" do
      merchant = Fixtures.merchant_fixture()
      provider = Fixtures.simulator_provider_fixture()
      _cred = Fixtures.simulator_credential_fixture(provider)

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

      {:ok, _payment} = payment |> Payment.transition_changeset("succeeded") |> Repo.update()
      {:ok, batch} = Settlement.create_batch(merchant.id, provider.id, "GHS", "simulation")

      stub_disbursement_success()

      assert {:ok, _settled} =
               SettlementProcessorWorker.perform(%Oban.Job{
                 args: %{"settlement_batch_id" => batch.id}
               })

      job =
        Repo.one(
          from j in Oban.Job,
            where: j.worker == "YagyeCore.Settlement.Workers.BankDispatchWorker",
            where: fragment("?->>'batch_id' = ?", j.args, ^batch.id)
        )

      assert job != nil
      assert job.queue == "settlement"
    end
  end
end
