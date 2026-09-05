# ADR-0023: ML Scoring Service Architecture

**Date:** 2026-09-05
**Status:** Accepted

---

## Context

P20 introduces four ML models that must score in the hot path of payment
processing. Two of them (`routing predictor`, `risk scorer`) are called
synchronously before a payment is dispatched. The latency budget for both
combined is ≤ 30ms at p99.

Two deployment options were considered:

**Option A — Python scoring service (FastAPI + ONNX Runtime)**
A separate container on `core_mesh` loading `.onnx` model weights and serving
HTTP. Core calls it via `Req` before routing.

**Option B — Native Elixir inference (Nx + Ortex)**
Load the `.onnx` model directly into `yagye_core` using `Ortex` (ONNX Runtime
NIF bindings). Zero network hop — inference runs inside the BEAM process.

---

## Decision

**Start with Option A (Python service); migrate hot models to Option B if
p99 latency budget is exceeded.**

### Rationale

Option A is faster to build and iterate on. Data scientists can retrain and
redeploy models independently of Core releases. ONNX is the interchange format
for both options — no lock-in.

Option B is reserved for models whose round-trip latency across the network
becomes the bottleneck. The routing predictor (simple tabular model,
microsecond inference) is the likely candidate for eventual migration to Nx.

### Scoring service contract

```
POST /score/routing
Body: {provider_code, network, amount_minor, hour_of_day, recent_error_rate}
Response: {provider_scores: [{provider_code: str, score: float}]}

POST /score/risk
Body: {msisdn_hash, merchant_id, amount_minor, hour_of_day,
       inter_arrival_ms, amount_deviation_pct}
Response: {risk_score: float, signals: [{name: str, contribution: float}]}
```

### Fallback behaviour

If the scoring service is unreachable or returns a 5xx, Core falls back to:
- Routing: static provider priority list (existing rule-based routing)
- Risk: existing flat `VelocityChecker` limits only

The fallback is automatic and logged as a span event. No payment is blocked
or delayed waiting for the scorer.

### Model update cadence

Models are retrained weekly using the DuckDB feature pipeline (ADR-0022).
New `.onnx` weights are written to `yagye-lake-curated/models/` in S3.
The scoring service polls for a new `latest.onnx` at startup and on a 1-hour
timer — zero-downtime model updates, no container restart required.

---

## Consequences

- A failed scoring service never blocks a payment — fallback is transparent.
- Models iterate independently of Core deploys.
- The ONNX interchange format keeps the migration path to Elixir Nx open.
- `core_mesh` network isolation means Portal and public traffic cannot reach
  the scoring service directly.
