# Mode Isolation

Last updated: 2026-10-18

```
MODE ISOLATION
================
Last updated: 2026-10-18

PURPOSE: Prevent simulation/sandbox/live data from mixing.
         Every record in both databases carries a mode column.

MODES:
  simulation  — fully in-process, no real provider calls
                Used for merchant testing and development
                All providers route to gateway_simulator

  sandbox     — real provider credentials, sandbox accounts
                Safe for merchant integration testing
                Real HTTP calls to provider sandbox environments

  live        — real money, real provider accounts
                Actual funds move. Full regulatory requirements apply.

──────────────────────────────────────────────────────────────────────────────

WHY A COLUMN, NOT A CONFIG FLAG:

  ✗ Config flag approach:
    YAGYE_MODE=sandbox in environment variables
    Pro: simple to switch
    Con: every query returns mixed data
         A single API key could read live records with sandbox config
         Settlement jobs might accidentally include simulation payments
         No data-layer enforcement — relies entirely on developer discipline

  ✓ Column-per-record approach:
    mode column on every row in both databases
    Pro: structural enforcement
         VerifyMode plug rejects cross-mode requests at API layer
         Queries filter on mode automatically
         Auditors can write trivially correct SQL: WHERE mode = 'live'
         Settlement, reporting, and reconciliation are mode-safe by default

  Cross-mode contamination has caused real financial losses at payment companies.
  The column-per-row design makes this structurally impossible — not just prohibited.

──────────────────────────────────────────────────────────────────────────────

END-TO-END ISOLATION: SIMULATION PAYMENT

  ┌──────────────────────────────────────────────────────────────────────┐
  │  Merchant uses simulation API key: sk_simulation_...                  │
  └───────────────────────────────────────┬──────────────────────────────┘
                                          │
                         ┌────────────────▼────────────────────────────────┐
                         │  Core: VerifyMode plug                           │
                         │  key.mode = 'simulation' ✓ (matches route)       │
                         │  If mismatch → 403 Forbidden                     │
                         └────────────────┬────────────────────────────────┘
                                          │
                         ┌────────────────▼────────────────────────────────┐
                         │  All DB writes carry mode = 'simulation':         │
                         │    payments.mode = 'simulation'                  │
                         │    payment_attempts.mode = 'simulation'          │
                         │    ledger_entries.mode = 'simulation'            │
                         │    ledger_postings.mode = 'simulation'           │
                         │    outbox_messages.mode = 'simulation'           │
                         └────────────────┬────────────────────────────────┘
                                          │
                         ┌────────────────▼────────────────────────────────┐
                         │  Routing: simulation payments → gateway_simulator │
                         │  ProviderCredential for 'simulation' mode         │
                         │  points to simulator URL, never real provider API  │
                         └────────────────┬────────────────────────────────┘
                                          │
                         ┌────────────────▼────────────────────────────────┐
                         │  gateway_simulator (stateless):                   │
                         │    MSISDN 024 100 0001 → success                  │
                         │    MSISDN 024 100 0002 → insufficient_funds       │
                         │    MSISDN 024 100 0003 → timeout                  │
                         │    X-Simulator-Outcome: refund_partial → etc.    │
                         └────────────────┬────────────────────────────────┘
                                          │
                         ┌────────────────▼────────────────────────────────┐
                         │  Outbox relay publishes event with mode=simulation │
                         │  Portal projection sets portal_payments.mode      │
                         │  = 'simulation'                                   │
                         │                                                   │
                         │  Portal views filter: WHERE mode = 'simulation'   │
                         │  Simulation payments ONLY visible in simulation UI │
                         └────────────────┬────────────────────────────────┘
                                          │
                         ┌────────────────▼────────────────────────────────┐
                         │  BankDispatchWorker (settlement):                 │
                         │    WHERE mode = 'live'                            │
                         │    Simulation batches are NEVER dispatched         │
                         │    to a real bank.                                │
                         └───────────────────────────────────────────────────┘

──────────────────────────────────────────────────────────────────────────────

MODE INHERITANCE:

  Every child record inherits the mode of its parent:

  payments.mode = 'live'
    └─ payment_attempts.mode = 'live'    (inherited)
    └─ ledger_entries.mode = 'live'       (inherited)
    └─ ledger_postings.mode = 'live'      (inherited)
    └─ outbox_messages.mode = 'live'      (inherited)
    └─ settlement_batches.mode = 'live'   (inherited)

  Mode cannot be changed after creation. A record created as 'simulation'
  will always be 'simulation'. There is no migration path between modes
  (a new payment must be created if the mode was wrong).

──────────────────────────────────────────────────────────────────────────────

THE VERIFY MODE PLUG:

  Placed in the :v1 pipeline, runs for every authenticated request.

  defmodule YagyeCoreWeb.Plugs.VerifyMode do
    def call(conn, _opts) do
      api_key = conn.assigns.current_api_key
      requested_mode = extract_mode_from_path_or_params(conn)

      if api_key.mode == requested_mode or requested_mode == nil do
        conn  # pass through
      else
        conn
        |> put_status(403)
        |> json(%{error: %{type: "authentication_error",
                           code: "mode_mismatch",
                           message: "This API key is for #{api_key.mode} mode."}})
        |> halt()
      end
    end
  end

  mode_mismatch is a 403 (not 401) because authentication succeeded —
  the key is valid. The request is forbidden due to a mode constraint.

──────────────────────────────────────────────────────────────────────────────

SIMULATION IN PORTAL:

  Merchant can switch between simulation and live modes in the portal UI.
  When in simulation mode:
    - Portal shows only simulation payments, balances, and deliveries
    - API key section shows the simulation key (sk_simulation_...)
    - Settlement shows "no live settlements" (correct)
    - All amounts displayed with a "SIM" badge

  Ops users can view both modes simultaneously (mode filter in the UI).
  This is necessary for ops to debug merchant integration issues.

──────────────────────────────────────────────────────────────────────────────

MODE AND THE DATA PLATFORM:

  At P14, Redpanda topics are mode-partitioned:
    payment.events.live
    payment.events.sandbox
    payment.events.simulation

  DuckDB analytics tables also carry a mode column.
  All ML training pipelines use WHERE mode = 'live' data only.
  Simulation data is used only for synthetic data generation experiments.
```
