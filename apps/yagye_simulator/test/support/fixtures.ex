defmodule Simulator.Fixtures do
  @moduledoc false

  alias Simulator.Accounts
  alias Simulator.Scenarios

  def scenario_fixture(attrs \\ %{}) do
    defaults = %{
      name: "test_scenario_#{System.unique_integer([:positive])}",
      is_default: false,
      active: true,
      latency_p50_ms: 50,
      latency_p95_ms: 200,
      latency_p99_ms: 500,
      success_rate: Decimal.new("0.900"),
      decline_rate: Decimal.new("0.050"),
      provider_error_rate: Decimal.new("0.010"),
      timeout_rate: Decimal.new("0.040"),
      timeout_creates_charge: false,
      duplicate_webhook_rate: Decimal.new("0.000"),
      out_of_order_rate: Decimal.new("0.000"),
      webhook_drop_rate: Decimal.new("0.000"),
      webhook_delay_max_ms: 0,
      three_ds_required_rate: Decimal.new("0.000"),
      auth_validity_hours: 24,
      supports_partial_capture: false,
      supports_multiple_capture: false,
      supports_incremental_auth: false,
      supports_void: true,
      arn_issued_at: "authorisation",
      settlement_discrepancy_rate: Decimal.new("0.000"),
      settlement_missing_line_rate: Decimal.new("0.000"),
      fee_drift_bps: 0
    }

    {:ok, scenario} = Scenarios.create(Map.merge(defaults, attrs))
    scenario
  end

  def account_fixture(attrs \\ %{}) do
    scenario = scenario_fixture()

    defaults = %{
      account_ref: "acct_test_#{System.unique_integer([:positive])}",
      display_name: "Test Account",
      webhook_url: "http://localhost:4000/webhooks/test",
      webhook_secret: "test_secret",
      currency: "GHS",
      default_scenario_id: scenario.id
    }

    {:ok, account} = Accounts.create_account(Map.merge(defaults, attrs))
    account
  end

  def account_with_key_fixture do
    account = account_fixture()
    raw_key = "test_key_#{System.unique_integer([:positive])}"
    {:ok, _key} = Accounts.issue_api_key(account.id, raw_key, "test")
    {account, raw_key}
  end
end
