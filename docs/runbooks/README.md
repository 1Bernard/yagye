# Runbooks

Operational procedures for common incidents and maintenance tasks.
Each file is a step-by-step guide written for an on-call engineer who may not
have built the component they are debugging.

## Index

| Runbook | Scenario |
|---|---|
| [outbox-relay-lag.md](outbox-relay-lag.md) | Outbox relay falls behind; portal projections stale |
| [payment-stuck-dispatching.md](payment-stuck-dispatching.md) | Payment stuck in `dispatching` state |
| [settlement-mismatch.md](settlement-mismatch.md) | Settlement variance ≠ 0 after provider report |
| [routing-no-match.md](routing-no-match.md) | Payment rejected with `no_matching_route` |
| [rate-limit-false-positive.md](rate-limit-false-positive.md) | Merchant hitting rate limit unexpectedly |

> Runbook files are stubs — fill them in as incidents occur. A runbook written
> during an incident is worth ten written in advance.

## First principles for any incident

1. **Identify the scope** — one merchant, one mode, one provider, or all traffic?
2. **Check Oban** — most async failures surface in the `oban_jobs` table with
   `state = 'retryable'` or `'discarded'`. Query: `SELECT * FROM oban_jobs WHERE state IN ('retryable','discarded') ORDER BY attempted_at DESC LIMIT 20;`
3. **Check the outbox** — relay lag = unprocessed rows in `outbox_messages`.
   Query: `SELECT count(*) FROM outbox_messages WHERE processed_at IS NULL;`
4. **Check logs** — structured JSON logs include `trace_id` (X-Request-ID /
   OTel trace context). Filter by `trace_id` to reconstruct the full request path
   across core and portal.
5. **Never hard-delete** — if a record looks wrong, investigate before touching it.
   Financial records are never physically removed (ADR-0020).
