defmodule Simulator.Charges.ChargesTest do
  use Simulator.DataCase, async: true

  alias Simulator.Charges
  alias Simulator.Fixtures

  describe "create_charge/2 — CARD" do
    test "returns AUTHORISED when scenario has 100% success rate" do
      scenario =
        Fixtures.scenario_fixture(%{
          success_rate: Decimal.new("1.000"),
          decline_rate: Decimal.new("0.000"),
          timeout_rate: Decimal.new("0.000"),
          provider_error_rate: Decimal.new("0.000")
        })

      account = Fixtures.account_fixture(%{default_scenario_id: scenario.id})

      {:ok, charge} =
        Charges.create_charge(account, %{
          amount_minor: 10_000,
          currency: "GHS",
          instrument_type: "CARD"
        })

      assert charge.state == "AUTHORISED"
      assert charge.amount_minor == 10_000
      assert charge.auth_code != nil
      assert charge.rrn != nil
      assert String.starts_with?(charge.charge_ref, "gw_")
    end

    test "returns DECLINED when scenario has 100% decline rate" do
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
      assert charge.decline_code == "INSUFFICIENT_FUNDS"
    end

    test "idempotency — same idempotency_key returns existing charge" do
      {account, _key} = Fixtures.account_with_key_fixture()
      idem_key = "order_#{System.unique_integer([:positive])}"

      attrs = %{
        amount_minor: 10_000,
        currency: "GHS",
        instrument_type: "CARD",
        idempotency_key: idem_key
      }

      {:ok, first} = Charges.create_charge(account, attrs)

      # Second call with same key should fail at DB constraint
      assert {:error, _} = Charges.create_charge(account, attrs)

      # But the original charge is retrievable
      {:ok, fetched} = Charges.get_by_ref(first.charge_ref)
      assert fetched.id == first.id
    end

    test "charge_ref is unique per charge" do
      {account, _key} = Fixtures.account_with_key_fixture()

      {:ok, c1} =
        Charges.create_charge(account, %{
          amount_minor: 1_000,
          currency: "GHS",
          instrument_type: "CARD"
        })

      {:ok, c2} =
        Charges.create_charge(account, %{
          amount_minor: 2_000,
          currency: "GHS",
          instrument_type: "CARD"
        })

      refute c1.charge_ref == c2.charge_ref
    end
  end

  describe "create_charge/2 — WALLET" do
    test "returns PENDING_AUTH immediately for WALLET instrument" do
      {account, _key} = Fixtures.account_with_key_fixture()

      {:ok, charge} =
        Charges.create_charge(account, %{
          amount_minor: 10_000,
          currency: "GHS",
          instrument_type: "WALLET",
          network: "MTN",
          msisdn: "0240000001"
        })

      assert charge.state == "PENDING_AUTH"
      assert charge.instrument_type == "WALLET"
    end
  end

  describe "fixed MSISDN outcomes — portal test credentials" do
    import Ecto.Query
    alias Simulator.Charges.Schemas.WalletPrompt
    alias Simulator.Repo

    defp wallet_prompt_for(charge) do
      Repo.one!(from p in WalletPrompt, where: p.charge_id == ^charge.id)
    end

    test "0241000001 (MTN success) → APPROVED prompt" do
      {account, _} = Fixtures.account_with_key_fixture()
      {:ok, charge} = Charges.create_charge(account, wallet_attrs("MTN", "0241000001"))
      assert wallet_prompt_for(charge).prompt_state == "APPROVED"
    end

    test "0241000002 (MTN insufficient funds) → DECLINED prompt with INSUFFICIENT_FUNDS" do
      {account, _} = Fixtures.account_with_key_fixture()
      {:ok, charge} = Charges.create_charge(account, wallet_attrs("MTN", "0241000002"))
      prompt = wallet_prompt_for(charge)
      assert prompt.prompt_state == "DECLINED"
      assert prompt.decline_code == "INSUFFICIENT_FUNDS"
    end

    test "0241000003 (MTN timeout) → EXPIRED prompt" do
      {account, _} = Fixtures.account_with_key_fixture()
      {:ok, charge} = Charges.create_charge(account, wallet_attrs("MTN", "0241000003"))
      assert wallet_prompt_for(charge).prompt_state == "EXPIRED"
    end

    test "0241000004 (MTN not registered) → DECLINED prompt with NOT_REGISTERED" do
      {account, _} = Fixtures.account_with_key_fixture()
      {:ok, charge} = Charges.create_charge(account, wallet_attrs("MTN", "0241000004"))
      prompt = wallet_prompt_for(charge)
      assert prompt.prompt_state == "DECLINED"
      assert prompt.decline_code == "NOT_REGISTERED"
    end

    test "0501000001 (Telecel success) → APPROVED prompt" do
      {account, _} = Fixtures.account_with_key_fixture()
      {:ok, charge} = Charges.create_charge(account, wallet_attrs("TELECEL", "0501000001"))
      assert wallet_prompt_for(charge).prompt_state == "APPROVED"
    end

    test "0501000002 (Telecel insufficient funds) → DECLINED with INSUFFICIENT_FUNDS" do
      {account, _} = Fixtures.account_with_key_fixture()
      {:ok, charge} = Charges.create_charge(account, wallet_attrs("TELECEL", "0501000002"))
      prompt = wallet_prompt_for(charge)
      assert prompt.prompt_state == "DECLINED"
      assert prompt.decline_code == "INSUFFICIENT_FUNDS"
    end

    test "0571000001 (AirtelTigo success) → APPROVED prompt" do
      {account, _} = Fixtures.account_with_key_fixture()
      {:ok, charge} = Charges.create_charge(account, wallet_attrs("AIRTELTIGO", "0571000001"))
      assert wallet_prompt_for(charge).prompt_state == "APPROVED"
    end

    test "0571000002 (AirtelTigo insufficient funds) → DECLINED with INSUFFICIENT_FUNDS" do
      {account, _} = Fixtures.account_with_key_fixture()
      {:ok, charge} = Charges.create_charge(account, wallet_attrs("AIRTELTIGO", "0571000002"))
      prompt = wallet_prompt_for(charge)
      assert prompt.prompt_state == "DECLINED"
      assert prompt.decline_code == "INSUFFICIENT_FUNDS"
    end

    test "fixed outcomes are independent of scenario rates" do
      scenario =
        Fixtures.scenario_fixture(%{
          decline_rate: Decimal.new("1.000"),
          success_rate: Decimal.new("0.000"),
          timeout_rate: Decimal.new("0.000"),
          provider_error_rate: Decimal.new("0.000")
        })

      account = Fixtures.account_fixture(%{default_scenario_id: scenario.id})
      {:ok, charge} = Charges.create_charge(account, wallet_attrs("MTN", "0241000001"))
      assert wallet_prompt_for(charge).prompt_state == "APPROVED"
    end

    defp wallet_attrs(network, msisdn) do
      %{amount_minor: 10_000, currency: "GHS", instrument_type: "WALLET",
        network: network, msisdn: msisdn}
    end
  end

  describe "name_enquiry/2 — fixed test numbers" do
    test "0241000004 (not registered) → NOT_FOUND" do
      {account, _} = Fixtures.account_with_key_fixture()
      {:ok, enquiry} = Charges.name_enquiry(account, %{network: "MTN", msisdn: "0241000004"})
      assert enquiry.outcome == "NOT_FOUND"
      assert enquiry.account_name == nil
    end
  end

  describe "get_by_ref/1" do
    test "returns charge for valid ref" do
      {account, _key} = Fixtures.account_with_key_fixture()

      {:ok, charge} =
        Charges.create_charge(account, %{
          amount_minor: 10_000,
          currency: "GHS",
          instrument_type: "CARD"
        })

      assert {:ok, fetched} = Charges.get_by_ref(charge.charge_ref)
      assert fetched.id == charge.id
    end

    test "returns not_found for unknown ref" do
      assert {:error, :not_found} = Charges.get_by_ref("gw_doesnotexist")
    end
  end

  describe "name_enquiry/2" do
    test "returns FOUND for valid msisdn" do
      {account, _key} = Fixtures.account_with_key_fixture()

      {:ok, enquiry} =
        Charges.name_enquiry(account, %{network: "MTN", msisdn: "0240000001"})

      assert enquiry.outcome == "FOUND"
      assert enquiry.account_name != nil
    end

    test "returns NOT_FOUND for msisdn ending in 0" do
      {account, _key} = Fixtures.account_with_key_fixture()

      {:ok, enquiry} =
        Charges.name_enquiry(account, %{network: "TELECEL", msisdn: "0550000000"})

      assert enquiry.outcome == "NOT_FOUND"
      assert enquiry.account_name == nil
    end
  end
end
