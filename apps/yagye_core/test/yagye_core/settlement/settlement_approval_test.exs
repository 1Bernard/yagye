defmodule YagyeCore.Settlement.SettlementApprovalTest do
  use YagyeCore.DataCase, async: true

  alias YagyeCore.{Fixtures, Repo}
  alias YagyeCore.Settlement
  alias YagyeCore.Settlement.Schemas.{MerchantSettlementControls, SettlementBatch}
  alias YagyeCore.Settlement.Workers.BankDispatchWorker

  setup do
    merchant = Fixtures.merchant_fixture()
    provider = Fixtures.provider_fixture(%{kind: "native_rail"})
    %{merchant: merchant, provider: provider}
  end

  defp insert_batch(merchant, provider, attrs \\ %{}) do
    Repo.insert!(
      %SettlementBatch{
        merchant_id: merchant.id,
        provider_id: provider.id,
        currency: "GHS",
        mode: "simulation",
        period_start: ~U[2026-09-01 00:00:00.000000Z],
        period_end: ~U[2026-09-02 00:00:00.000000Z],
        gross_amount: 500_000,
        payment_count: 5,
        state: "settled"
      }
      |> Map.merge(attrs)
    )
  end

  defp insert_controls(merchant, attrs \\ %{}) do
    Repo.insert!(
      %MerchantSettlementControls{
        merchant_id: merchant.id,
        approval_threshold: 100_000,
        approver_user_codes: ["USR-APPROVER1"],
        updated_by: "test"
      }
      |> Map.merge(attrs)
    )
  end

  # ── gate_cleared? (tested via BankDispatchWorker behaviour) ──────────────────

  describe "gate_cleared? / get_settlement_controls" do
    test "returns true when no controls configured", %{merchant: merchant} do
      assert Settlement.get_settlement_controls(merchant.id) == nil
    end

    test "upsert creates controls", %{merchant: merchant} do
      assert {:ok, controls} =
               Settlement.upsert_settlement_controls(merchant.id, %{
                 approval_threshold: 50_000,
                 approver_user_codes: ["USR-A"],
                 updated_by: "test"
               })

      assert controls.approval_threshold == 50_000
      assert controls.approver_user_codes == ["USR-A"]
    end

    test "upsert is idempotent (updates existing)", %{merchant: merchant} do
      insert_controls(merchant)

      assert {:ok, updated} =
               Settlement.upsert_settlement_controls(merchant.id, %{
                 approval_threshold: 200_000,
                 approver_user_codes: ["USR-A", "USR-B"],
                 updated_by: "test"
               })

      assert updated.approval_threshold == 200_000
      assert updated.approver_user_codes == ["USR-A", "USR-B"]
    end
  end

  # ── approve_batch_dispatch ────────────────────────────────────────────────────

  describe "approve_batch_dispatch/2" do
    test "succeeds and transitions batch to settled + re-enqueues worker", %{
      merchant: merchant,
      provider: provider
    } do
      insert_controls(merchant)
      batch = insert_batch(merchant, provider, %{state: "awaiting_approval"})

      assert {:ok, updated} = Settlement.approve_batch_dispatch(batch.id, "USR-APPROVER1")
      assert updated.state == "settled"
      assert updated.dispatch_approved_by == "USR-APPROVER1"
      assert updated.dispatch_approved_at != nil

      assert_enqueued(worker: BankDispatchWorker, args: %{"batch_id" => batch.id})
    end

    test "fails with unauthorized_approver for user not in list", %{
      merchant: merchant,
      provider: provider
    } do
      insert_controls(merchant)
      batch = insert_batch(merchant, provider, %{state: "awaiting_approval"})

      assert {:error, :unauthorized_approver} =
               Settlement.approve_batch_dispatch(batch.id, "USR-INTRUDER")
    end

    test "fails with not_awaiting_approval for batch in wrong state", %{
      merchant: merchant,
      provider: provider
    } do
      insert_controls(merchant)
      batch = insert_batch(merchant, provider, %{state: "settled"})

      assert {:error, :not_awaiting_approval} =
               Settlement.approve_batch_dispatch(batch.id, "USR-APPROVER1")
    end

    test "fails with no_controls when merchant has no controls", %{
      merchant: merchant,
      provider: provider
    } do
      batch = insert_batch(merchant, provider, %{state: "awaiting_approval"})

      assert {:error, :no_controls} =
               Settlement.approve_batch_dispatch(batch.id, "USR-APPROVER1")
    end
  end

  # ── reject_batch_dispatch ─────────────────────────────────────────────────────

  describe "reject_batch_dispatch/3" do
    test "succeeds and transitions batch to dispatch_rejected", %{
      merchant: merchant,
      provider: provider
    } do
      insert_controls(merchant)
      batch = insert_batch(merchant, provider, %{state: "awaiting_approval"})

      assert {:ok, updated} =
               Settlement.reject_batch_dispatch(batch.id, "USR-APPROVER1", "Amount too high")

      assert updated.state == "dispatch_rejected"
      assert updated.dispatch_rejected_by == "USR-APPROVER1"
      assert updated.dispatch_rejection_reason == "Amount too high"
    end

    test "fails with not_awaiting_approval for wrong state", %{
      merchant: merchant,
      provider: provider
    } do
      insert_controls(merchant)
      batch = insert_batch(merchant, provider, %{state: "settled"})

      assert {:error, :not_awaiting_approval} =
               Settlement.reject_batch_dispatch(batch.id, "USR-APPROVER1", "nope")
    end
  end

  # ── BankDispatchWorker gate behaviour ────────────────────────────────────────

  describe "BankDispatchWorker gate" do
    test "enters approval gate when threshold crossed", %{merchant: merchant, provider: provider} do
      insert_controls(merchant, %{approval_threshold: 100_000})
      batch = insert_batch(merchant, provider, %{gross_amount: 500_000, state: "settled"})

      assert :ok = perform_job(BankDispatchWorker, %{"batch_id" => batch.id})

      reloaded = Repo.get!(SettlementBatch, batch.id)
      assert reloaded.state == "awaiting_approval"
    end

    test "bypasses gate when no controls configured", %{merchant: merchant, provider: provider} do
      batch = insert_batch(merchant, provider, %{state: "settled"})

      # Will attempt the provider call; without a credential/simulator it errors,
      # but it must NOT enter awaiting_approval — it should try to dispatch.
      perform_job(BankDispatchWorker, %{"batch_id" => batch.id})

      reloaded = Repo.get!(SettlementBatch, batch.id)
      assert reloaded.state != "awaiting_approval"
    end

    test "bypasses gate when dispatch_approved_by is set", %{
      merchant: merchant,
      provider: provider
    } do
      insert_controls(merchant, %{approval_threshold: 100_000})

      batch =
        insert_batch(merchant, provider, %{
          gross_amount: 500_000,
          state: "settled",
          dispatch_approved_by: "USR-APPROVER1"
        })

      # Tries to call provider, not enter gate
      perform_job(BankDispatchWorker, %{"batch_id" => batch.id})

      reloaded = Repo.get!(SettlementBatch, batch.id)
      assert reloaded.state != "awaiting_approval"
    end
  end
end
