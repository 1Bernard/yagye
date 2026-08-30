# Common Incidents Runbook

Procedures for the most likely production incidents. Each entry states: how
to confirm the issue, immediate mitigation, root-cause investigation, and
resolution.

---

## 1. Payment Stuck in `processing`

**Symptoms:** Merchant reports a payment shows `processing` for more than
5 minutes. Customer may have been charged.

**Confirm:**
```sql
-- Core DB
SELECT id, public_id, state, inserted_at, updated_at
FROM payments
WHERE public_id = 'pay_…';

SELECT id, state, provider_code, provider_reference, error_code, inserted_at
FROM payment_attempts
WHERE payment_id = '…'
ORDER BY inserted_at;
```

**Likely causes:**
1. **Oban job failed silently** — the `PaymentDispatchWorker` job errored and
   exhausted retries.
2. **Provider webhook not received** — the provider called back but the webhook
   endpoint was unreachable or returned a non-2xx.
3. **Provider timeout** — the provider did not respond within the timeout window.

**Investigation:**
```sql
-- Check Oban job state
SELECT id, state, attempt, max_attempts, errors, scheduled_at
FROM oban_jobs
WHERE args->>'payment_id' = '…'
ORDER BY inserted_at DESC;
```

Check application logs for the `payment_id` around `inserted_at`. Check
provider dashboard for the `provider_reference` if an attempt was made.

**Resolution:**
- If the provider reports success: manually transition via internal API or
  direct DB update (with ledger entries — do not skip the accounting):
  ```elixir
  # Rails console (Core)
  payment = YagyeCore.Payments.get_payment("pay_…") |> elem(1)
  YagyeCore.Payments.confirm_payment(payment, %{provider_reference: "…"})
  ```
- If the provider reports failure: call `YagyeCore.Payments.fail_payment/2`.
- If the provider is unreachable: wait and re-enqueue the dispatch job.

---

## 2. Projection Lag — Dashboard Shows Stale Balances

**Symptoms:** Portal dashboard shows a `last_applied_at` freshness indicator
that is more than 5 minutes behind. Merchant balance does not reflect recent
payments.

**Confirm:**
```sql
-- Portal DB
SELECT merchant_code, available_balance, last_applied_at
FROM proj_merchant_balances
WHERE merchant_code = '…';
```

**Likely causes:**
1. **Outbox relay backlog** — `outbox_messages` has a growing queue.
2. **Karafka consumer lag** — the portal consumer group is behind.
3. **Projection worker errors** — `MerchantBalanceProjection` is failing.

**Investigation:**
```sql
-- Core DB — outbox queue depth
SELECT COUNT(*), MIN(inserted_at) as oldest
FROM outbox_messages
WHERE processed_at IS NULL;

-- Core DB — Oban projection job errors
SELECT errors FROM oban_jobs
WHERE worker = 'YagyeCore.Outbox.Workers.OutboxRelayWorker'
  AND state = 'retryable'
ORDER BY inserted_at DESC
LIMIT 5;
```

Check Karafka consumer group lag in the Redpanda console.

**Resolution:**
- If relay is backed up: increase `@batch_size` in `OutboxRelayWorker`
  temporarily, or manually trigger a relay cycle.
- If projection worker is erroring: fix the root cause, then let Oban retry.
  Do not manually update projection rows — the worker owns that state.
- If Karafka consumer is lagging: check for consumer crashes in portal logs.
  Restart the consumer process.

---

## 3. Settlement Mismatch

**Symptoms:** A settlement is in `mismatched` state. The `variance` column is
non-zero — Yagye's expected net differs from the provider's reported net.

**Confirm:**
```sql
-- Core DB
SELECT public_id, expected_net, reported_net, variance,
       provider_settlement_reference, value_date
FROM settlements
WHERE state = 'mismatched'
  AND merchant_id = '…';
```

**Likely causes:**
1. **Fee calculation discrepancy** — Yagye's fee model diverges from the
   provider's actual deductions (changed rates not reflected in pricing config).
2. **Missing payments** — one or more payments included in Yagye's expected
   gross were not included in the provider's report.
3. **Currency rounding** — rare, but possible if the provider rounds differently.

**Investigation:**
```sql
-- Compare Yagye's settlement items vs provider report
SELECT si.payment_id, si.gross_amount, si.fee_amount, si.net_amount
FROM settlement_items si
WHERE si.settlement_id = '…'
ORDER BY si.payment_id;
```

Cross-reference with the provider's itemised statement for the same
`value_date` range.

**Resolution:**
- If fee rates changed: update the pricing config for the affected provider
  and re-run the settlement matching (`Settlement.run_matching/1`).
- If payments are missing from provider report: raise a dispute with the
  provider. Do not manually adjust settlement figures.
- If variance is within tolerance (e.g. < 1 GHS due to rounding): create an
  adjustment entry and manually transition to `matched` — document the reason.

---

## 4. API Key Suspected Compromised

**Symptoms:** Merchant reports unexpected API calls. Ops receives alert for
unusual payment volume or velocity limit breaches.

**Immediate mitigation:**
```bash
# Revoke the key immediately via API
curl -X DELETE https://api.yagye.com/v1/merchants/{merchant_id}/keys/{key_id} \
  -H "Authorization: Bearer <ops-key>"
```

Or via internal console:
```elixir
key = YagyeCore.Merchants.get_api_key!(key_id)
YagyeCore.Merchants.revoke_api_key(key)
```

**Investigation:**
```sql
-- All requests made with this key in the last 24h
SELECT path, method, ip_address, inserted_at
FROM api_requests
WHERE merchant_id = '…'
  AND inserted_at > now() - interval '24 hours'
ORDER BY inserted_at DESC;
```

Check for unexpected IPs, unusual paths, or bulk payment creation.

**Resolution:**
1. Revoke the compromised key (done above — sets `revoked_at`).
2. Issue a new key to the merchant.
3. Review all payments created via the compromised key — flag any suspicious
   ones for manual review.
4. Notify the merchant.

---

## 5. Database Connection Exhaustion

**Symptoms:** Core API returns 500 errors. Logs show
`DBConnection.ConnectionError: connection not available`. Ecto pool is exhausted.

**Confirm:**
```sql
-- On the PostgreSQL server
SELECT count(*), state, application_name
FROM pg_stat_activity
WHERE datname = 'yagye_core_prod'
GROUP BY state, application_name
ORDER BY count DESC;
```

**Likely causes:**
1. **Traffic spike** — more concurrent requests than the pool can handle.
2. **Slow queries holding connections** — long-running queries keeping pool
   slots occupied.
3. **Oban runaway** — too many concurrent Oban workers competing for
   connections.

**Investigation:**
```sql
-- Find long-running queries
SELECT pid, now() - pg_stat_activity.query_start AS duration, query, state
FROM pg_stat_activity
WHERE (now() - pg_stat_activity.query_start) > interval '5 seconds'
  AND datname = 'yagye_core_prod';
```

**Immediate mitigation:**
- Kill long-running queries: `SELECT pg_terminate_backend(pid);`
- Temporarily reduce Oban queue concurrency in the running instance.
- If traffic spike: add a node or enable rate limiting at the load balancer.

**Resolution:**
- If query performance: add missing index or optimise the slow query.
- If sustained traffic: add a core node and configure PgBouncer (see
  `docs/architecture/scaling-playbook.md` §4).
- If Oban: review queue `limit` settings in `config/config.exs`.

---

## 6. Idempotency Key Collision (False Duplicate)

**Symptoms:** Merchant reports that a payment request returned a cached response
from a previous, unrelated request. Two different payments share the same
idempotency key.

**Confirm:**
```sql
SELECT id, merchant_id, key, expires_at, response_status
FROM idempotency_keys
WHERE key = '…';
```

**Cause:** The merchant's integration is reusing idempotency keys across
different requests (bug in their SDK or integration code).

**Resolution:**
- This is a merchant integration error, not a Yagye bug.
- Idempotency keys are scoped to `(merchant_id, key)` — two different merchants
  can use the same key value without collision.
- If a merchant accidentally reused a key within the 24h window and needs the
  second request processed: delete the stale idempotency key row (the only
  permitted delete on this table) and ask the merchant to retry.

---

## Operational Contacts

| System | Who to contact |
|---|---|
| MTN MoMo | MTN Ghana API support |
| Vodafone Cash | Telecel Ghana technical team |
| Stripe | Stripe support dashboard |
| Flutterwave | Flutterwave partner portal |
| Paystack | Paystack developer support |
| Redpanda | Redpanda Cloud support |
| Infra / DB | Internal on-call rotation |
