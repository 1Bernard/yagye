# ADR-0027: Override `adapter_module` (not `code`) for Simulation Dispatch

**Status:** Accepted  
**Date:** 2026-11-06  
**Deciders:** Bernard  

---

## Context

Yagye runs payments in `simulation` mode for development and load testing.
In simulation mode, all payment API calls must be routed to `SimulatorAdapter`
regardless of the actual MNO provider (MTN, Telecel, AirtelTigo). The DB holds
real provider rows — `mtn_momo_gh`, `telecel_cash_gh`, `airteltigo_money_gh` —
each with their own `adapter_module` column set to their real adapter class
(`"MTNMomoAdapter"`, etc.).

The routing layer in `Providers.resolve_sim_provider/1` resolves the per-MNO
provider struct and must ensure `ProviderAdapter.for_provider/1` dispatches to
`SimulatorAdapter`, not to the real MNO adapter.

`ProviderAdapter.for_provider/1` has two dispatch paths:
1. `code: "simulator"` → `SimulatorAdapter` (clause 1)
2. `adapter_module: <binary>` → that module (clause 2)
3. All others → `SimulatorAdapter` (clause 3, the default fallback)

MTN's row has `adapter_module: "MTNMomoAdapter"`. Without intervention, clause 2
dispatches to the (not-yet-built) `MTNMomoAdapter`.

## Decision Candidates

### Option A: Override `provider.code` to `"simulator"`

Override the struct's `code` field so clause 1 of `for_provider` matches:

```elixir
{:ok, {%{provider | code: "simulator"}, credential_map, %{source: :static}}}
```

**Problem:** `provider.code` is used downstream in many places:
- **Outbox events** — `payment_attempt.provider.code` is included as
  `provider_code` in every outbox event payload. Overriding to `"simulator"`
  means all outbox events report `provider_code: "simulator"` regardless of
  which MNO was used. This corrupts the Bronze training data: the Silver ETL
  cannot distinguish MTN from Telecel from AirtelTigo payments; they all appear
  as `provider_code: "simulator"`.
- **ML training labels** — provider health, per-network success rates, and
  routing model training features all depend on `provider_code` being the real
  MNO code. Corrupted codes mean the routing model trains on synthetic labels,
  not real ones.
- **Settlement batching** — settlement runs scope by `provider_id`, which is
  already the real UUID. The code override therefore does not break settlement,
  but it creates inconsistency between `provider_code` and `provider_id`.

### Option B: Override `adapter_module` to `SimulatorAdapter`

Override only the field that `for_provider` clause 2 reads:

```elixir
sim_adapter = "YagyeCore.Payments.Adapters.SimulatorAdapter"
{:ok, {%{provider | adapter_module: sim_adapter}, credential_map, %{source: :static}}}
```

**Effect:**
- `for_provider` clause 2 now dispatches to `SimulatorAdapter`. ✓
- `provider.code` remains `"mtn_momo_gh"` (or whichever MNO). Outbox events
  carry the correct `provider_code`. ✓
- ML training data receives real per-MNO provider codes. ✓
- `provider.id` is already the real MNO UUID (unchanged). Settlement correct. ✓

## Decision

**Option B: override `adapter_module`.**

Preserving `provider.code` through simulation mode is essential for data
quality. The routing model cannot learn to distinguish MTN from Telecel
performance if both appear as `"simulator"` in training labels. The impact
of Option A extends beyond the development environment — Bronze data written
during simulation runs is source material for the first production model, so
corrupt labels there delay a working model by weeks.

## Consequences

### Positive
- Outbox events carry real MNO `provider_code` values in simulation mode.
- Bronze/Silver/Gold training data has correct per-MNO labels from day one.
- `PaymentDispatchWorker` calls the correct adapter without special casing.

### Gotcha: `PaymentStatusCheckWorker`

`PaymentStatusCheckWorker` resolves the adapter independently of
`PaymentDispatchWorker`. It queries the DB directly for the provider by
`provider_id`. The DB row has the original `adapter_module` (e.g.
`"MTNMomoAdapter"`), so it would dispatch to the real (unbuilt) adapter.

**Fix:** The status check worker checks `payment.mode` and short-circuits
to `ProviderAdapter.adapter()` (the globally configured adapter, which is
`SimulatorAdapter` in dev Docker) for simulation mode:

```elixir
defp adapter_for_attempt(_attempt, "simulation"), do: {:ok, ProviderAdapter.adapter()}
defp adapter_for_attempt(%PaymentAttempt{provider_id: provider_id}, _mode) do
  case Providers.get_provider(provider_id) do
    {:ok, provider} -> {:ok, ProviderAdapter.for_provider(provider)}
    {:error, _} = err -> err
  end
end
```

### Gotcha: Network code casing

`payment.metadata["network"]` can arrive as lowercase (`"mtn"`, `"telecel"`)
from some payment creation paths. The `@sim_network_providers` map uses
uppercase keys (`"MTN"`, `"TELECEL"`). Without `String.upcase/1`, Telecel and
AirtelTigo fall back to the generic simulator provider instead of their MNO
providers.

**Fix:** Normalise before map lookup:

```elixir
code = Map.get(@sim_network_providers, network && String.upcase(network), @simulator_code)
```

## Files Changed

- `apps/yagye_core/lib/yagye_core/providers/providers.ex` — `resolve_sim_provider/1`
- `apps/yagye_core/lib/yagye_core/payments/workers/payment_status_check_worker.ex` — `adapter_for_attempt/2`
