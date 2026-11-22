# ADR-0023: ML / AI Scoring Service Architecture

**Date:** 2026-09-05
**Updated:** 2026-11-22
**Status:** Accepted

---

## Context

P20 introduces risk scoring and routing enrichment in the hot path of payment
processing. Two enrichment calls (`routing enrichment`, `risk scorer`) are made
synchronously before a payment is dispatched. The latency budget for both
combined is ≤ 30ms at p99.

At P20 launch, no trained tabular ML models exist — training data accumulates
from live payments and the data platform, with ONNX-based tabular models planned
for post-P22 (see `docs/data-engineering/ml-architecture.md`). The scoring
service ships with LLM-based enrichment and rule-based fallbacks in shadow mode.

---

## Decision

**`yagye_scoring`: Python FastAPI service on `core_mesh` powered by Anthropic
Claude LLM + OpenLIT (LLM observability) + Langfuse (LLM tracing).**

### Current implementation (P20)

The scoring service uses Claude (via the Anthropic API) for risk enrichment and
routing suggestions. The LLM receives only non-PII signals extracted by Core:

- For risk: `risk_score`, `risk_decision`, `mode` — no MSISDN, customer name,
  or card numbers are ever sent to the LLM.
- For routing: provider health metrics, network code, amount tier, hour-of-day.

Observability is provided by OpenLIT (latency, token usage, cost per call) and
Langfuse (prompt tracing, regression tracking across model updates).

### Scoring service contract

```
POST /score/routing
Body: {network, amount_minor, hour_of_day, recent_error_rate}
Response: {provider_scores: [{provider_code: str, score: float}]}

POST /score/risk
Body: {risk_score, risk_decision, mode, amount_minor, hour_of_day,
       inter_arrival_ms, amount_deviation_pct}
Response: {risk_score: float, signals: [{name: str, contribution: float}]}
```

### Fallback behaviour

If the scoring service is unreachable or returns a 5xx, Core falls back to:
- Routing: static provider priority list (existing rule-based routing)
- Risk: existing flat `VelocityChecker` limits only

The fallback is automatic and logged as a span event. No payment is blocked
or delayed waiting for the scorer.

### Future: tabular ML models (post-P22)

Once sufficient live payment data has accumulated, ONNX-based tabular models
(XGBoost routing predictor, LightGBM risk scorer) will be trained using the
DuckDB Gold feature pipeline (ADR-0022) and deployed alongside the LLM path.
The same FastAPI service will serve both paths — the LLM enrichment and the
ONNX models are additive, not mutually exclusive. See
`docs/data-engineering/ml-architecture.md` for the full model training and
serving design.

---

## Consequences

- A failed scoring service never blocks a payment — fallback is transparent.
- LLM enrichment is immediately available without waiting for training data.
- Security: PII stays in Core; the scoring service receives only derived signals.
- OpenLIT + Langfuse give per-request cost and quality visibility from day one.
- `core_mesh` network isolation means Portal and public traffic cannot reach
  the scoring service directly.
- The ONNX migration path remains open — the FastAPI container hosts both paths.
