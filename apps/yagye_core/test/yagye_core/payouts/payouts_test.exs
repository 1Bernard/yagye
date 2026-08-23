defmodule YagyeCore.Payouts.PayoutsTest do
  use YagyeCore.DataCase, async: true

  alias YagyeCore.Fixtures
  alias YagyeCore.Payouts
  alias YagyeCore.Payouts.Schemas.Payout
  alias YagyeCore.Payouts.Workers.PayoutSagaWorker
  alias YagyeCore.Repo

  setup do
    merchant = Fixtures.approved_merchant_fixture()
    %{merchant: merchant}
  end

  defp destination_fixture(merchant, attrs \\ %{}) do
    create_attrs =
      Map.merge(
        %{
          mode: "live",
          kind: "mobile_money",
          currency: "GHS",
          account_details: %{"msisdn" => "0241234567", "network" => "MTN"}
        },
        Map.drop(attrs, [:verification_state])
      )

    {:ok, dest} = Payouts.create_destination(merchant.id, create_attrs)

    # create_changeset doesn't cast verification_state; set it directly
    verification_state = Map.get(attrs, :verification_state, "verified")
    Ecto.Changeset.change(dest, verification_state: verification_state) |> Repo.update!()
  end

  defp payout_fixture(merchant, destination, attrs \\ %{}) do
    {:ok, payout} =
      Payouts.create_payout(
        merchant.id,
        Map.merge(
          %{
            destination_id: destination.id,
            mode: "live",
            amount: 50_000,
            currency: "GHS",
            destination_type: destination.kind,
            destination_fingerprint: destination.fingerprint,
            scheduled_for: Date.utc_today()
          },
          attrs
        )
      )

    payout
  end

  describe "create_payout/2" do
    test "inserts a payout in scheduled state and enqueues the saga worker", %{merchant: merchant} do
      dest = destination_fixture(merchant)

      assert {:ok, %Payout{} = payout} =
               Payouts.create_payout(merchant.id, %{
                 destination_id: dest.id,
                 mode: "live",
                 amount: 50_000,
                 currency: "GHS",
                 destination_type: dest.kind,
                 destination_fingerprint: dest.fingerprint,
                 scheduled_for: Date.utc_today()
               })

      assert payout.state == "scheduled"
      assert payout.public_id =~ "pot_"
      assert_enqueued(worker: PayoutSagaWorker, args: %{"payout_id" => payout.id})
    end
  end

  describe "create_destination/2" do
    test "encrypts account_details and produces a fingerprint", %{merchant: merchant} do
      {:ok, dest} =
        Payouts.create_destination(merchant.id, %{
          mode: "live",
          kind: "bank",
          currency: "GHS",
          account_details: %{"account_number" => "1234567890", "bank_code" => "GCB"}
        })

      assert dest.account_details_encrypted != nil
      assert dest.fingerprint != nil
      assert dest.verification_state == "unverified"
    end

    test "prevents duplicate destinations via fingerprint uniqueness", %{merchant: merchant} do
      attrs = %{
        mode: "live",
        kind: "bank",
        currency: "GHS",
        account_details: %{"account_number" => "1234567890", "bank_code" => "GCB"}
      }

      {:ok, _first} = Payouts.create_destination(merchant.id, attrs)
      assert {:error, %Ecto.Changeset{}} = Payouts.create_destination(merchant.id, attrs)
    end
  end

  describe "PayoutSagaWorker — state machine" do
    test "fails payout when destination is inactive", %{merchant: merchant} do
      dest = destination_fixture(merchant)
      Payouts.deactivate_destination(dest)

      payout = payout_fixture(merchant, dest)

      perform_job(PayoutSagaWorker, %{"payout_id" => payout.id})

      assert Repo.get!(Payout, payout.id).state == "failed"
      assert Repo.get!(Payout, payout.id).failure_code == "destination_inactive"
    end

    test "fails payout when destination is unverified", %{merchant: merchant} do
      dest = destination_fixture(merchant, %{verification_state: "unverified"})

      payout = payout_fixture(merchant, dest)

      perform_job(PayoutSagaWorker, %{"payout_id" => payout.id})

      assert Repo.get!(Payout, payout.id).failure_code == "destination_unverified"
    end

    test "fails payout when merchant has insufficient payable balance", %{merchant: merchant} do
      dest = destination_fixture(merchant)
      payout = payout_fixture(merchant, dest)

      # No ledger entries created → payable balance is 0 < 50_000
      perform_job(PayoutSagaWorker, %{"payout_id" => payout.id})

      assert Repo.get!(Payout, payout.id).failure_code == "insufficient_payable_balance"
    end
  end
end
