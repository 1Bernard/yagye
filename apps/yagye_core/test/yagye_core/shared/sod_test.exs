defmodule YagyeCore.Shared.SodTest do
  use YagyeCore.DataCase, async: true

  alias YagyeCore.Fixtures
  alias YagyeCore.Payouts
  alias YagyeCore.Payouts.Schemas.{Payout, PayoutDestination}
  alias YagyeCore.Reserves
  alias YagyeCore.Reserves.Schemas.MerchantReserve

  setup do
    merchant = Fixtures.approved_merchant_fixture()
    %{merchant: merchant}
  end

  # ── MerchantReserve ──────────────────────────────────────────────────────────

  describe "MerchantReserve.approve_changeset/2" do
    test "returns error when approved_by equals created_by", %{merchant: merchant} do
      {:ok, reserve} =
        Reserves.create_policy(merchant.id, %{
          kind: "rolling",
          percentage_bps: 500,
          hold_days: 90,
          currency: "GHS",
          mode: "simulation",
          created_by: "user:usr_alice"
        })

      cs = MerchantReserve.approve_changeset(reserve, "user:usr_alice")

      assert {:approved_by, {"must differ from created_by", _}} =
               Enum.find(cs.errors, &match?({:approved_by, _}, &1))
    end

    test "is valid when approved_by differs from created_by", %{merchant: merchant} do
      {:ok, reserve} =
        Reserves.create_policy(merchant.id, %{
          kind: "rolling",
          percentage_bps: 500,
          hold_days: 90,
          currency: "GHS",
          mode: "simulation",
          created_by: "user:usr_alice"
        })

      cs = MerchantReserve.approve_changeset(reserve, "user:usr_bob")
      assert cs.valid?
    end

    test "allows NULL created_by (system-created) without SoD enforcement", %{merchant: merchant} do
      {:ok, reserve} =
        Reserves.create_policy(merchant.id, %{
          kind: "rolling",
          percentage_bps: 500,
          hold_days: 90,
          currency: "GHS",
          mode: "simulation"
        })

      # created_by is nil → nullable condition: no SoD violation
      cs = MerchantReserve.approve_changeset(reserve, "user:usr_alice")
      assert cs.valid?
    end
  end

  # ── PayoutDestination ────────────────────────────────────────────────────────

  describe "PayoutDestination.verify_changeset/2" do
    test "returns error when verified_by equals added_by", %{merchant: merchant} do
      {:ok, dest} =
        Payouts.create_destination(merchant.id, %{
          mode: "simulation",
          kind: "bank",
          currency: "GHS",
          account_details: %{"account_number" => "111", "bank_code" => "GCB"},
          added_by: "user:usr_alice"
        })

      cs = PayoutDestination.verify_changeset(dest, "user:usr_alice")
      assert Keyword.has_key?(cs.errors, :verified_by)
    end

    test "is valid when verified_by differs from added_by", %{merchant: merchant} do
      {:ok, dest} =
        Payouts.create_destination(merchant.id, %{
          mode: "simulation",
          kind: "bank",
          currency: "GHS",
          account_details: %{"account_number" => "222", "bank_code" => "GCB"},
          added_by: "user:usr_alice"
        })

      cs = PayoutDestination.verify_changeset(dest, "user:usr_bob")
      assert cs.valid?
    end

    test "allows NULL added_by (merchant self-service) without SoD enforcement", %{
      merchant: merchant
    } do
      {:ok, dest} =
        Payouts.create_destination(merchant.id, %{
          mode: "simulation",
          kind: "bank",
          currency: "GHS",
          account_details: %{"account_number" => "333", "bank_code" => "GCB"}
        })

      cs = PayoutDestination.verify_changeset(dest, "user:usr_alice")
      assert cs.valid?
    end
  end

  # ── Payout ──────────────────────────────────────────────────────────────────

  describe "Payout.approve_changeset/2" do
    test "returns error when approved_by equals requested_by", %{merchant: merchant} do
      {:ok, dest} =
        Payouts.create_destination(merchant.id, %{
          mode: "simulation",
          kind: "mobile_money",
          currency: "GHS",
          account_details: %{"msisdn" => "0241234567"}
        })

      {:ok, payout} =
        Payouts.create_payout(merchant.id, %{
          destination_id: dest.id,
          mode: "simulation",
          amount: 50_000,
          currency: "GHS",
          destination_type: dest.kind,
          destination_fingerprint: dest.fingerprint,
          scheduled_for: Date.utc_today(),
          requested_by: "user:usr_alice"
        })

      cs = Payout.approve_changeset(payout, "user:usr_alice")
      assert Keyword.has_key?(cs.errors, :approved_by)
    end

    test "is valid when approved_by differs from requested_by", %{merchant: merchant} do
      {:ok, dest} =
        Payouts.create_destination(merchant.id, %{
          mode: "simulation",
          kind: "mobile_money",
          currency: "GHS",
          account_details: %{"msisdn" => "0249876543"}
        })

      {:ok, payout} =
        Payouts.create_payout(merchant.id, %{
          destination_id: dest.id,
          mode: "simulation",
          amount: 50_000,
          currency: "GHS",
          destination_type: dest.kind,
          destination_fingerprint: dest.fingerprint,
          scheduled_for: Date.utc_today(),
          requested_by: "user:usr_alice"
        })

      cs = Payout.approve_changeset(payout, "user:usr_bob")
      assert cs.valid?
    end

    test "allows NULL requested_by (system-scheduled) without SoD enforcement", %{
      merchant: merchant
    } do
      {:ok, dest} =
        Payouts.create_destination(merchant.id, %{
          mode: "simulation",
          kind: "mobile_money",
          currency: "GHS",
          account_details: %{"msisdn" => "0200000001"}
        })

      {:ok, payout} =
        Payouts.create_payout(merchant.id, %{
          destination_id: dest.id,
          mode: "simulation",
          amount: 50_000,
          currency: "GHS",
          destination_type: dest.kind,
          destination_fingerprint: dest.fingerprint,
          scheduled_for: Date.utc_today()
        })

      cs = Payout.approve_changeset(payout, "user:usr_alice")
      assert cs.valid?
    end
  end

  # ── Context wrappers ─────────────────────────────────────────────────────────
  # These tests verify that the context functions (not just the changesets) correctly
  # route SoD enforcement all the way through to the DB.

  describe "Reserves.approve_policy/2" do
    test "persists approval when actors differ", %{merchant: merchant} do
      {:ok, reserve} =
        Reserves.create_policy(merchant.id, %{
          kind: "rolling",
          percentage_bps: 500,
          hold_days: 90,
          currency: "GHS",
          mode: "live",
          created_by: "user:usr_alice"
        })

      assert {:ok, approved} = Reserves.approve_policy(reserve, "user:usr_bob")
      assert approved.approved_by == "user:usr_bob"
    end

    test "returns changeset error when actor is the same", %{merchant: merchant} do
      {:ok, reserve} =
        Reserves.create_policy(merchant.id, %{
          kind: "rolling",
          percentage_bps: 500,
          hold_days: 90,
          currency: "GHS",
          mode: "live",
          created_by: "user:usr_alice"
        })

      assert {:error, %Ecto.Changeset{} = cs} = Reserves.approve_policy(reserve, "user:usr_alice")
      assert Keyword.has_key?(cs.errors, :approved_by)
    end
  end

  describe "Payouts.verify_destination/2" do
    test "persists verification when actors differ", %{merchant: merchant} do
      {:ok, dest} =
        Payouts.create_destination(merchant.id, %{
          mode: "live",
          kind: "bank",
          currency: "GHS",
          account_details: %{"account_number" => "444", "bank_code" => "GCB"},
          added_by: "user:usr_alice"
        })

      assert {:ok, verified} = Payouts.verify_destination(dest, "user:usr_bob")
      assert verified.verified_by == "user:usr_bob"
      assert verified.verification_state == "verified"
    end

    test "returns changeset error when actor is the same", %{merchant: merchant} do
      {:ok, dest} =
        Payouts.create_destination(merchant.id, %{
          mode: "live",
          kind: "bank",
          currency: "GHS",
          account_details: %{"account_number" => "555", "bank_code" => "GCB"},
          added_by: "user:usr_alice"
        })

      assert {:error, %Ecto.Changeset{} = cs} = Payouts.verify_destination(dest, "user:usr_alice")
      assert Keyword.has_key?(cs.errors, :verified_by)
    end
  end

  describe "Payouts.approve_payout/2" do
    test "persists approval when actors differ", %{merchant: merchant} do
      {:ok, dest} =
        Payouts.create_destination(merchant.id, %{
          mode: "live",
          kind: "mobile_money",
          currency: "GHS",
          account_details: %{"msisdn" => "0200000002"}
        })

      {:ok, payout} =
        Payouts.create_payout(merchant.id, %{
          destination_id: dest.id,
          mode: "live",
          amount: 50_000,
          currency: "GHS",
          destination_type: dest.kind,
          destination_fingerprint: dest.fingerprint,
          scheduled_for: Date.utc_today(),
          requested_by: "user:usr_alice"
        })

      assert {:ok, approved} = Payouts.approve_payout(payout, "user:usr_bob")
      assert approved.approved_by == "user:usr_bob"
    end

    test "returns changeset error when actor is the same", %{merchant: merchant} do
      {:ok, dest} =
        Payouts.create_destination(merchant.id, %{
          mode: "live",
          kind: "mobile_money",
          currency: "GHS",
          account_details: %{"msisdn" => "0200000003"}
        })

      {:ok, payout} =
        Payouts.create_payout(merchant.id, %{
          destination_id: dest.id,
          mode: "live",
          amount: 50_000,
          currency: "GHS",
          destination_type: dest.kind,
          destination_fingerprint: dest.fingerprint,
          scheduled_for: Date.utc_today(),
          requested_by: "user:usr_alice"
        })

      assert {:error, %Ecto.Changeset{} = cs} = Payouts.approve_payout(payout, "user:usr_alice")
      assert Keyword.has_key?(cs.errors, :approved_by)
    end
  end
end
