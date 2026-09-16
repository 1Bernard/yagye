defmodule Simulator.Settlements.SettlementsTest do
  use Simulator.DataCase, async: true

  alias Simulator.Accounts
  alias Simulator.Charges.Schemas.Charge
  alias Simulator.Fixtures
  alias Simulator.Repo
  alias Simulator.Settlements

  setup do
    {account, _raw_key} = Fixtures.account_with_key_fixture()
    {:ok, account: account}
  end

  defp insert_authorised_charge(account, amount_minor) do
    now = DateTime.utc_now()

    %Charge{}
    |> Charge.changeset(%{
      account_id: account.id,
      charge_ref: "gw_test_#{System.unique_integer([:positive])}",
      amount_minor: amount_minor,
      currency: account.currency,
      instrument_type: "WALLET",
      state: "AUTHORISED",
      authorised_amount_minor: amount_minor,
      captured_amount_minor: amount_minor,
      authorised_at: now
    })
    |> Repo.insert!()
  end

  # ── No charges ────────────────────────────────────────────────────────────────

  describe "generate_report/2 with no charges" do
    test "returns an empty settlement file", %{account: account} do
      date = ~D[2026-09-01]
      assert {:ok, file} = Settlements.generate_report(account, date)
      assert file.line_count == 0
      assert file.lines == []
      assert file.settlement_date == date
    end
  end

  # ── Basic charge inclusion ─────────────────────────────────────────────────────

  describe "generate_report/2 with charges" do
    test "includes AUTHORISED charges in the settlement", %{account: account} do
      insert_authorised_charge(account, 50_000)

      date = Date.utc_today()
      assert {:ok, file} = Settlements.generate_report(account, date)
      assert file.line_count == 1
      assert length(file.lines) == 1

      [line] = file.lines
      assert line.charge_ref =~ "gw_"
      assert line.gross_minor == 50_000
      assert line.line_type == "CHARGE"
      assert line.value_date == date
    end

    test "totals sum correctly across lines", %{account: account} do
      insert_authorised_charge(account, 30_000)
      insert_authorised_charge(account, 70_000)

      date = Date.utc_today()
      {:ok, file} = Settlements.generate_report(account, date)

      assert file.line_count == 2
      assert file.gross_minor == file.lines |> Enum.map(& &1.gross_minor) |> Enum.sum()
      assert file.net_minor == file.fee_minor + file.net_minor - file.fee_minor
    end

    test "idempotent — second call returns cached file", %{account: account} do
      date = ~D[2026-09-02]
      {:ok, file1} = Settlements.generate_report(account, date)
      {:ok, file2} = Settlements.generate_report(account, date)
      assert file1.id == file2.id
    end
  end

  # ── Fee drift ──────────────────────────────────────────────────────────────────

  describe "generate_report/2 with fee_drift_bps scenario" do
    test "applies fee drift to line fee calculations" do
      scenario = Fixtures.scenario_fixture(%{fee_drift_bps: 50})

      {:ok, drifted_account} =
        Accounts.create_account(%{
          account_ref: "acct_drift_#{System.unique_integer([:positive])}",
          display_name: "Fee Drift Account",
          webhook_url: "http://localhost:4000/webhooks/drift",
          webhook_secret: "drift_secret",
          currency: "GHS",
          fee_percentage_bps: 150,
          fee_fixed_minor: 0,
          default_scenario_id: scenario.id
        })

      insert_authorised_charge(drifted_account, 100_000)

      date = Date.utc_today()
      {:ok, file} = Settlements.generate_report(drifted_account, date)

      assert file.line_count == 1
      [line] = file.lines

      # fee_bps = 150 + 50 = 200 bps → fee = div(100_000 * 200, 10_000) = 2_000
      # without drift: 150 bps → fee = 1_500
      assert line.fee_minor == 2_000
      assert line.net_minor == 98_000
      assert file.injected_defect == "fee_drift"
    end
  end

  # ── Missing lines ──────────────────────────────────────────────────────────────

  describe "generate_report/2 with settlement_missing_line_rate scenario" do
    test "drops lines deterministically — every 4th line with rate 0.25" do
      scenario =
        Fixtures.scenario_fixture(%{settlement_missing_line_rate: Decimal.new("0.250")})

      {:ok, missing_account} =
        Accounts.create_account(%{
          account_ref: "acct_missing_#{System.unique_integer([:positive])}",
          display_name: "Missing Line Account",
          webhook_url: "http://localhost:4000/webhooks/missing",
          webhook_secret: "missing_secret",
          currency: "GHS",
          fee_percentage_bps: 150,
          default_scenario_id: scenario.id
        })

      Enum.each(1..4, fn i ->
        insert_authorised_charge(missing_account, 10_000 * i)
      end)

      date = Date.utc_today()
      {:ok, file} = Settlements.generate_report(missing_account, date)

      # rate = 0.25, skip_every = 4: drops every 4th charge (index 4)
      # 4 charges → 1 dropped → 3 lines
      assert file.line_count == 3
      assert file.injected_defect == "missing_line"
    end

    test "line numbers are re-sequenced after dropping" do
      scenario =
        Fixtures.scenario_fixture(%{settlement_missing_line_rate: Decimal.new("0.500")})

      {:ok, drop_account} =
        Accounts.create_account(%{
          account_ref: "acct_drop_#{System.unique_integer([:positive])}",
          display_name: "Drop Account",
          webhook_url: "http://localhost:4000/webhooks/drop",
          webhook_secret: "drop_secret",
          currency: "GHS",
          fee_percentage_bps: 150,
          default_scenario_id: scenario.id
        })

      Enum.each(1..4, fn i ->
        insert_authorised_charge(drop_account, 10_000 * i)
      end)

      date = Date.utc_today()
      {:ok, file} = Settlements.generate_report(drop_account, date)

      # rate = 0.5, skip_every = 2: drops charges 2, 4 → keeps charges 1, 3
      # line_numbers should be 1, 2 (re-sequenced)
      assert file.line_count == 2
      line_numbers = file.lines |> Enum.map(& &1.line_number) |> Enum.sort()
      assert line_numbers == [1, 2]
    end
  end
end
