# ADR-0013: Permanent Gateway Simulator as the Anti-Corruption Layer

**Date:** 2026-08-20
**Status:** Accepted

## Context

Phase 4 required integration with payment providers (MTN MoMo, card acquirers).
Real provider sandboxes have three problems:

1. **They are unreliable.** A provider sandbox going down breaks CI. Flakiness in
   CI erodes trust in the test suite.
2. **They are uncontrollable.** You cannot instruct a real sandbox to produce a
   timeout 4% of the time, a provider error 1% of the time, and an authorisation
   the rest. Deterministic failure testing is impossible.
3. **They use their own vocabulary.** A card acquirer says `AUTHORISED`; a mobile
   money provider says `APPROVED`. Allowing that vocabulary into the core domain
   couples domain logic to provider-specific strings.

Two approaches were considered:

**Option A — test doubles / mocks**: replace real HTTP calls with in-process
Mox mocks in tests. Fast. The problem: a mock is a description of what you believe
the provider does, not what it actually does. Mocks cannot test the HTTP layer,
serialisation, or the full request/response cycle. They are useful for unit tests
but cannot stand alone as integration coverage.

**Option B — a permanent simulator application**: build a real Phoenix application
that speaks the provider's wire protocol, runs in CI, and uses its own separate
PostgreSQL database. The simulator is not a fake — it is a model of the contract.
It must be harder than any real provider: it can simulate timeouts, errors, and
duplicate webhooks on demand.

## Decision

Build and permanently maintain `yagye_simulator` as a **real Phoenix application**:

- **Separate database**: `gateway_simulator_dev`, `gateway_simulator_test`. Sharing
  Yagye's database would simulate a single process, not a distributed system.
- **Deliberate vocabulary mismatch**: `charge_ref` not `payment_id`, `PENDING_AUTH`
  not `requires_action`, `WALLET` not `mobile_money`. If any simulator word appears
  inside `YagyeCore.Payments`, the ACL has failed. CI enforces this via the
  `Boundary` library.
- **`ProviderAdapter` behaviour**: `YagyeCore.Payments.ProviderAdapter` defines the
  contract (`charge/3`, `refund/3`, `name_enquiry/2`). `SimulatorAdapter` implements
  it for development and CI. Real provider adapters will implement the same behaviour
  in production. Swapping adapters requires no changes to domain code.
- **`OutcomeEngine`**: probabilistic outcome resolution driven by `Scenario` rates.
  A test can pin a deterministic outcome by passing a `seed`; a load test exercises
  the full rate distribution.
- **Stays in CI forever**: no real provider will send a duplicate webhook 40 seconds
  late on demand. The simulator can and does.

## Consequences

### Positive
- CI never depends on a third-party sandbox. The test suite is fully hermetic.
- Failure scenarios (timeout, provider_error, duplicate webhook) are testable with
  a deterministic seed — broken tests are reproducible, not just "try again".
- The vocabulary boundary is machine-enforced. Domain logic is protected from
  provider-specific language by compile-time checks, not convention.
- New provider adapters can be developed and tested locally without real credentials.
- The simulator doubles as a chaos tool: changing scenario rates simulates a
  degraded provider during load testing.

### Negative / Trade-offs
- Two applications to maintain instead of one. Schema changes that affect the
  provider API require coordinated migrations in both databases.
- `SimulatorAdapter` is a third implementation of every provider operation
  (real adapter, mock, simulator). Must be kept in sync with the `ProviderAdapter`
  behaviour contract.
- The simulator does not cover `external_psp` providers (Stripe, Flutterwave, etc.
  used in Model B). Those have their own vendor sandboxes. Extending the simulator
  to cover them would duplicate what those vendors already provide.
