# Bootstrap seed for the gateway simulator.
# Safe to re-run — skips records that already exist.
#
# This seed creates:
#   1. A "happy path" default scenario (90% success, small failure rates)
#   2. A "chaos" scenario for stress testing
#   3. The Yagye platform account (matches yagye_core's provider_credentials seed)
#   4. A platform API key: sim_dev_key (matches what yagye_core seeds put in Vault)

alias Simulator.Accounts
alias Simulator.Accounts.Schemas.{Account, ApiKey}
alias Simulator.Repo
alias Simulator.Scenarios
alias Simulator.Scenarios.Schemas.Scenario

IO.puts("\n=== Gateway Simulator bootstrap ===\n")

# ── 1. Default (happy path) scenario ──────────────────────────────────────────

default_scenario =
  case Repo.get_by(Scenario, name: "happy_path") do
    %Scenario{} = s ->
      IO.puts("Scenario [happy_path]  : already exists")
      s

    nil ->
      {:ok, s} =
        Scenarios.create(%{
          name: "happy_path",
          is_default: true,
          active: true,
          latency_p50_ms: 80,
          latency_p95_ms: 400,
          latency_p99_ms: 1_200,
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
        })

      IO.puts("Scenario [happy_path]  : created (id: #{s.id}) — set as default")
      s
  end

# ── 2. Chaos scenario ─────────────────────────────────────────────────────────

case Repo.get_by(Scenario, name: "chaos") do
  %Scenario{} ->
    IO.puts("Scenario [chaos]       : already exists")

  nil ->
    {:ok, _s} =
      Scenarios.create(%{
        name: "chaos",
        is_default: false,
        active: true,
        latency_p50_ms: 800,
        latency_p95_ms: 3_000,
        latency_p99_ms: 9_000,
        success_rate: Decimal.new("0.600"),
        decline_rate: Decimal.new("0.150"),
        provider_error_rate: Decimal.new("0.100"),
        timeout_rate: Decimal.new("0.150"),
        timeout_creates_charge: true,
        duplicate_webhook_rate: Decimal.new("0.200"),
        out_of_order_rate: Decimal.new("0.150"),
        webhook_drop_rate: Decimal.new("0.100"),
        webhook_delay_max_ms: 40_000,
        three_ds_required_rate: Decimal.new("0.300"),
        auth_validity_hours: 1,
        supports_partial_capture: true,
        supports_multiple_capture: true,
        supports_incremental_auth: false,
        supports_void: false,
        arn_issued_at: "settlement",
        settlement_discrepancy_rate: Decimal.new("0.050"),
        settlement_missing_line_rate: Decimal.new("0.030"),
        fee_drift_bps: 10
      })

    IO.puts("Scenario [chaos]       : created — high failure rates, late ARN, dropped webhooks")
end

# ── 3. Yagye platform account ─────────────────────────────────────────────────

account =
  case Repo.get_by(Account, account_ref: "acct_yagye_platform") do
    %Account{} = a ->
      IO.puts("Account [yagye_platform]: already exists")
      a

    nil ->
      {:ok, a} =
        Accounts.create_account(%{
          account_ref: "acct_yagye_platform",
          display_name: "Yagye Payment Orchestration",
          webhook_url: "http://localhost:4000/webhooks/simulator",
          webhook_secret: "sim_webhook_secret_dev",
          webhook_signing_algorithm: "HS256",
          settlement_cadence: "daily",
          settlement_cutoff_time: ~T[23:59:00],
          settlement_timezone: "Africa/Accra",
          currency: "GHS",
          fee_percentage_bps: 150,
          fee_fixed_minor: 0,
          default_scenario_id: default_scenario.id
        })

      IO.puts("Account [yagye_platform]: created (id: #{a.id})")
      a
  end

# ── 4. Platform API key ───────────────────────────────────────────────────────

# This key MUST match the api_key in yagye_core's simulator credential seed:
#   Vault.encrypt_map(%{"api_key" => "sim_dev_key"})
raw_key = "sim_dev_key"

case Repo.get_by(ApiKey, account_id: account.id) do
  %ApiKey{} ->
    IO.puts("API key                : already exists")

  nil ->
    {:ok, _key} = Accounts.issue_api_key(account.id, raw_key, "yagye-core-dev")
    IO.puts("API key                : created (raw: #{raw_key})")
    IO.puts("                         This matches yagye_core priv/repo/seeds.exs")
end

IO.puts("\n=== Done ===")
IO.puts("Admin UI : http://localhost:4100/admin/scenarios")
IO.puts("API docs : http://localhost:4100/api/swaggerui\n")
