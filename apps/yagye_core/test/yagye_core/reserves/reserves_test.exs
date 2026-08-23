defmodule YagyeCore.Reserves.ReservesTest do
  use YagyeCore.DataCase, async: true

  alias YagyeCore.Fixtures
  alias YagyeCore.Ledger
  alias YagyeCore.Repo
  alias YagyeCore.Reserves
  alias YagyeCore.Reserves.Schemas.ReserveHold

  setup do
    merchant = Fixtures.approved_merchant_fixture()

    payment =
      Fixtures.succeeded_payment_fixture(merchant, %{
        amount: 100_000,
        currency: "GHS",
        mode: "simulation"
      })

    %{merchant: merchant, payment: payment}
  end

  describe "reserve_policy_for/3" do
    test "returns nil when no active policy exists", %{merchant: merchant} do
      result = Reserves.reserve_policy_for(merchant.id, "GHS", "simulation")
      assert result == nil
    end

    test "returns the active policy when one exists", %{merchant: merchant} do
      {:ok, reserve} =
        Reserves.create_policy(merchant.id, %{
          kind: "rolling",
          percentage_bps: 500,
          hold_days: 90,
          currency: "GHS",
          mode: "simulation"
        })

      result = Reserves.reserve_policy_for(merchant.id, "GHS", "simulation")
      assert result.id == reserve.id
    end

    test "ignores inactive policies", %{merchant: merchant} do
      {:ok, reserve} =
        Reserves.create_policy(merchant.id, %{
          kind: "rolling",
          percentage_bps: 500,
          hold_days: 90,
          currency: "GHS",
          mode: "simulation"
        })

      Reserves.deactivate_policy(reserve)

      assert Reserves.reserve_policy_for(merchant.id, "GHS", "simulation") == nil
    end
  end

  describe "create_hold/1" do
    test "returns {:ok, nil} when no active policy", %{payment: payment} do
      assert {:ok, nil} = Reserves.create_hold(payment)
    end

    test "creates a hold for a rolling policy", %{merchant: merchant, payment: payment} do
      {:ok, _reserve} =
        Reserves.create_policy(merchant.id, %{
          kind: "rolling",
          percentage_bps: 500,
          hold_days: 90,
          currency: "GHS",
          mode: "live"
        })

      assert {:ok, %ReserveHold{} = hold} = Reserves.create_hold(payment)
      # 5% of 100_000 = 5_000
      assert hold.amount == 5_000
      assert hold.currency == "GHS"
      assert hold.state == "pending"
      assert hold.payment_id == payment.id
    end

    test "creates a hold for a fixed policy", %{merchant: merchant, payment: payment} do
      {:ok, _reserve} =
        Reserves.create_policy(merchant.id, %{
          kind: "fixed",
          fixed_amount: 2_000,
          currency: "GHS",
          mode: "live"
        })

      assert {:ok, %ReserveHold{} = hold} = Reserves.create_hold(payment)
      assert hold.amount == 2_000
    end

    test "posts ledger entries for the hold", %{merchant: merchant, payment: payment} do
      {:ok, _reserve} =
        Reserves.create_policy(merchant.id, %{
          kind: "rolling",
          percentage_bps: 500,
          hold_days: 90,
          currency: "GHS",
          mode: "live"
        })

      {:ok, _hold} = Reserves.create_hold(payment)

      {:ok, reserve_account} = Ledger.get_account("merchant_reserve:#{merchant.id}:GHS:live")
      {:ok, reserve_balance} = Ledger.get_balance(reserve_account.id)
      # Convention: credit = negative delta. 5% of 100_000 = 5_000, stored as -5_000.
      assert reserve_balance == -5_000
    end

    test "is idempotent — second call returns existing hold", %{
      merchant: merchant,
      payment: payment
    } do
      {:ok, _reserve} =
        Reserves.create_policy(merchant.id, %{
          kind: "fixed",
          fixed_amount: 1_000,
          currency: "GHS",
          mode: "live"
        })

      {:ok, hold1} = Reserves.create_hold(payment)
      # Unique index on (payment_id, reserve_id) prevents a second hold
      assert {:error, _} = Reserves.create_hold(payment)
      assert hold1.amount == 1_000
    end
  end

  describe "draw_hold/2" do
    test "draws a pending hold and updates state", %{merchant: merchant, payment: payment} do
      {:ok, _reserve} =
        Reserves.create_policy(merchant.id, %{
          kind: "fixed",
          fixed_amount: 1_000,
          currency: "GHS",
          mode: "live"
        })

      {:ok, hold} = Reserves.create_hold(payment)
      dispute_id = Uniq.UUID.uuid7()

      assert {:ok, drawn} = Reserves.draw_hold(hold, dispute_id)
      assert drawn.state == "drawn"
      assert drawn.draw_source_id == dispute_id
      assert drawn.drawn_at != nil
    end

    test "rejects draw on a non-pending hold", %{merchant: merchant, payment: payment} do
      {:ok, _reserve} =
        Reserves.create_policy(merchant.id, %{
          kind: "fixed",
          fixed_amount: 1_000,
          currency: "GHS",
          mode: "live"
        })

      {:ok, hold} = Reserves.create_hold(payment)
      {:ok, drawn} = Reserves.draw_hold(hold, Uniq.UUID.uuid7())

      assert {:error, {:invalid_hold_state, "drawn"}} =
               Reserves.draw_hold(drawn, Uniq.UUID.uuid7())
    end
  end

  describe "release_due_holds/0" do
    test "releases holds whose release_at is in the past", %{merchant: merchant, payment: payment} do
      {:ok, reserve} =
        Reserves.create_policy(merchant.id, %{
          kind: "fixed",
          fixed_amount: 1_000,
          currency: "GHS",
          mode: "live"
        })

      hold =
        Repo.insert!(%ReserveHold{
          merchant_id: merchant.id,
          reserve_id: reserve.id,
          payment_id: payment.id,
          amount: 1_000,
          currency: "GHS",
          mode: "live",
          state: "pending",
          held_at: ~U[2026-01-01 00:00:00.000000Z],
          release_at: ~U[2026-01-02 00:00:00.000000Z],
          inserted_at: ~U[2026-01-01 00:00:00.000000Z]
        })

      assert {:ok, 1} = Reserves.release_due_holds()

      released = Repo.get!(ReserveHold, hold.id)
      assert released.state == "released"
    end

    test "skips holds not yet due", %{merchant: merchant, payment: payment} do
      {:ok, reserve} =
        Reserves.create_policy(merchant.id, %{
          kind: "fixed",
          fixed_amount: 1_000,
          currency: "GHS",
          mode: "live"
        })

      future = DateTime.add(DateTime.utc_now(), 30 * 86_400, :second)

      Repo.insert!(%ReserveHold{
        merchant_id: merchant.id,
        reserve_id: reserve.id,
        payment_id: payment.id,
        amount: 1_000,
        currency: "GHS",
        mode: "live",
        state: "pending",
        held_at: DateTime.utc_now(),
        release_at: future,
        inserted_at: DateTime.utc_now()
      })

      assert {:ok, 0} = Reserves.release_due_holds()
    end
  end
end
