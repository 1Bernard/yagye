defmodule Simulator.Refunds.RefundsTest do
  use Simulator.DataCase, async: true

  alias Simulator.Charges
  alias Simulator.Fixtures
  alias Simulator.Refunds

  defp authorised_charge(account) do
    scenario =
      Fixtures.scenario_fixture(%{
        success_rate: Decimal.new("1.000"),
        decline_rate: Decimal.new("0.000"),
        timeout_rate: Decimal.new("0.000"),
        provider_error_rate: Decimal.new("0.000")
      })

    account = %{account | default_scenario_id: scenario.id, default_scenario: scenario}

    {:ok, charge} =
      Charges.create_charge(account, %{
        amount_minor: 10_000,
        currency: "GHS",
        instrument_type: "CARD"
      })

    charge
  end

  describe "create_refund/3" do
    test "creates a full refund against an AUTHORISED charge" do
      {account, _key} = Fixtures.account_with_key_fixture()
      charge = authorised_charge(account)

      assert {:ok, refund} =
               Refunds.create_refund(account, charge.charge_ref, %{amount_minor: 10_000})

      assert refund.state == "OK"
      assert refund.amount_minor == 10_000
      assert refund.currency == "GHS"
      assert String.starts_with?(refund.refund_ref, "RF_")
    end

    test "creates a partial refund" do
      {account, _key} = Fixtures.account_with_key_fixture()
      charge = authorised_charge(account)

      assert {:ok, refund} =
               Refunds.create_refund(account, charge.charge_ref, %{amount_minor: 3_000})

      assert refund.state == "OK"
      assert refund.amount_minor == 3_000
    end

    test "rejects refund exceeding original amount" do
      {account, _key} = Fixtures.account_with_key_fixture()
      charge = authorised_charge(account)

      assert {:error, :amount_exceeds_original} =
               Refunds.create_refund(account, charge.charge_ref, %{amount_minor: 99_999})
    end

    test "rejects refund for unknown charge_ref" do
      {account, _key} = Fixtures.account_with_key_fixture()

      assert {:error, :not_found} =
               Refunds.create_refund(account, "gw_doesnotexist", %{amount_minor: 1_000})
    end

    test "rejects refund for DECLINED charge" do
      scenario =
        Fixtures.scenario_fixture(%{
          decline_rate: Decimal.new("1.000"),
          success_rate: Decimal.new("0.000"),
          timeout_rate: Decimal.new("0.000"),
          provider_error_rate: Decimal.new("0.000")
        })

      account = Fixtures.account_fixture(%{default_scenario_id: scenario.id})

      {:ok, charge} =
        Charges.create_charge(account, %{
          amount_minor: 5_000,
          currency: "GHS",
          instrument_type: "CARD"
        })

      assert charge.state == "DECLINED"

      assert {:error, {:not_refundable, "DECLINED"}} =
               Refunds.create_refund(account, charge.charge_ref, %{amount_minor: 5_000})
    end

    test "rejects refund from a different account" do
      {account_a, _} = Fixtures.account_with_key_fixture()
      {account_b, _} = Fixtures.account_with_key_fixture()
      charge = authorised_charge(account_a)

      assert {:error, :not_found} =
               Refunds.create_refund(account_b, charge.charge_ref, %{amount_minor: 1_000})
    end
  end

  describe "get_by_ref/1" do
    test "returns refund for valid ref" do
      {account, _key} = Fixtures.account_with_key_fixture()
      charge = authorised_charge(account)
      {:ok, refund} = Refunds.create_refund(account, charge.charge_ref, %{amount_minor: 1_000})

      assert {:ok, fetched} = Refunds.get_by_ref(refund.refund_ref)
      assert fetched.id == refund.id
    end

    test "returns not_found for unknown ref" do
      assert {:error, :not_found} = Refunds.get_by_ref("RF_doesnotexist")
    end
  end
end
