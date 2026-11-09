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

## 7. Webhook Delivery Retry Flood

**Symptoms:** RabbitMQ management UI shows `yagye.webhooks.delivery` queue
depth climbing rapidly. Delivery logs show the same event cycling through
`failed` → retry → `failed` at high frequency, never exhausting its attempts.

**Likely cause:** Messages were being requeued by Broadway before the
`on_failure: :reject` fix (old `:reject_and_requeue` setting). Alternatively,
a large backlog of stale tasks exists from a previous misconfiguration.

**Confirm:**
```bash
# Check queue depth and message rate
curl -u guest:guest http://localhost:15672/api/queues/%2F/yagye.webhooks.delivery

# Check recent delivery attempts in Core DB
SELECT endpoint_id, event_id, attempt, state, inserted_at
FROM merchant_webhook_deliveries
ORDER BY inserted_at DESC
LIMIT 20;
```

**Key distinction — purge vs delete:**
- **Purging** only clears messages sitting in the queue. Broadway may have up to
  `prefetch_count` (20) messages already fetched into memory. After a purge,
  those in-flight messages are nacked back when they fail and reappear in the
  queue.
- **Deleting** the queue discards everything, including in-flight prefetched
  messages. Broadway reconnects and recreates the queue clean.

**Resolution:**
```bash
# Delete the queue entirely (Broadway will recreate on reconnect)
curl -u guest:guest -X DELETE \
  http://localhost:15672/api/queues/%2F/yagye.webhooks.delivery

# Verify queue was recreated and is empty
curl -u guest:guest \
  http://localhost:15672/api/queues/%2F/yagye.webhooks.delivery \
  | jq '{messages, consumers}'
```

If the flood was caused by stale messages pointing to an unreachable URL
(e.g. localhost URL in a production task), delete the queue to clear them.
The Oban `WebhookDeliveryRetryWorker` will schedule legitimate retries from
the DB; stale tasks are discarded.

---

## 8. Webhook Endpoint Auto-Suspended

**Symptoms:** Merchant reports webhooks have stopped arriving. Portal shows
the endpoint with `consecutive_failures` near or at 50 and `active: false`.

**Confirm:**
```sql
-- Core DB
SELECT public_id, url, active, consecutive_failures, disabled_at
FROM merchant_webhook_endpoints
WHERE merchant_id = '…';
```

**Cause:** The endpoint accumulated 50 consecutive delivery failures. The
`DeliveryPipeline` automatically sets `active = false` and records `disabled_at`
via `MerchantWebhookEndpoint.disable_changeset/1`.

**Resolution:**
1. Identify the root cause of delivery failures (endpoint URL unreachable,
   signing secret mismatch, merchant server returning non-2xx).
2. Once the merchant has fixed their endpoint:
```bash
# Re-enable via internal API
curl -X PATCH https://api.yagye.com/internal/merchants/{code}/webhook-endpoints/{id} \
  -H "X-Service-Token: <token>" \
  -d '{"active": true}'
```
Or directly if needed:
```elixir
endpoint = YagyeCore.MerchantWebhooks.get_endpoint_by_public_id!("whe_…")
YagyeCore.MerchantWebhooks.update_endpoint(endpoint, %{"active" => true})
```
3. Send a test event from the Portal developer console to confirm delivery.
4. The Portal's `WebhookEventsConsumer` will project the re-enabled state
   via the `webhook.endpoint.updated` event; the consecutive failures badge
   will clear when the next successful delivery resets the counter.

---

## 9. ML Scoring Service Returns Rule-Based Fallback

**Symptoms:** Grafana logs show `model_version: rule_based_fallback` on every
`scoring.routing.shadow` log line. Scores are always `0.85` regardless of
provider or time of day. The scoring service `/ready` endpoint returns healthy.

**Confirm:**
```bash
# Check model status at startup
docker logs docker-yagye_scoring-1 2>&1 | grep model_status

# Expected when ONNX loaded:
#   model_status model=routing_native_rail loaded=true version=v20261106_195509
# Fallback (no ONNX):
#   model_status model=routing_native_rail loaded=false version=rule_based_fallback
```

**Likely causes:**
1. **No champion.flag in S3** — no model has been trained and promoted yet.
   This is expected before the first training run.
2. **Model not promoted after training** — training completed but the gate
   blocked promotion (challenger AUC-PR did not exceed champion by ≥ 0.5%).
3. **S3 unreachable at startup** — the scoring container cannot reach Floci/AWS;
   model load silently skipped (see `model_s3_skip` log entries).
4. **Wrong version logged despite model loaded** — model is loaded (is_loaded=True,
   real score visible in logs) but version shows `rule_based_fallback`. This
   means `load_from_path` was called without the `version=` parameter and tried
   to parse the version from the temp file path which contains no version segment.

**Investigation:**
```bash
# Check S3 for the champion flag
aws --endpoint-url http://localhost:4566 s3 ls s3://yagye-ml-models/routing_native_rail/

# Check what champion.flag contains
aws --endpoint-url http://localhost:4566 s3 cp \
  s3://yagye-ml-models/routing_native_rail/champion.flag -
```

**Resolution:**
- **No flag yet:** Run the full Bronze → Silver → Gold → training pipeline.
  The gate will promote the first model automatically (no existing champion
  to compare against).
- **Flag exists but model still shows fallback:** Restart the scoring container;
  it only loads models at startup. `docker restart docker-yagye_scoring-1`.
- **Wrong version logged:** This is a `load_from_path` bug — ensure `version=`
  is passed from the champion flag content, not omitted. The model IS serving
  real ONNX scores despite the wrong version label.
- **S3 unreachable:** Check `AWS_S3_HOST`, `AWS_ACCESS_KEY_ID`, and
  `AWS_SECRET_ACCESS_KEY` env vars in the scoring container. Verify Floci is
  running: `docker ps | grep floci`.

---

## 10. Payments Returning 307 Redirect on Webhook Delivery

**Symptoms:** Simulator webhooks reach Core but are redirected (307). Payment
stays in `processing`. Logs show `redirect_response` or HTTP 307 from Core.
Only occurs in Docker dev (not staging/prod with real TLS).

**Confirm:**
```bash
# From inside the simulator container, test Core's webhook endpoint directly
docker exec docker-yagye_simulator-1 \
  curl -v http://yagye_core:4000/webhooks/provider/simulator \
  -d '{}' -H 'Content-Type: application/json'
# A 307 response means force_ssl is active and upgrading HTTP → HTTPS.
```

**Root cause:** `force_ssl: [hsts: true]` was set at compile time in `config/prod.exs`
instead of at runtime in `config/runtime.exs`. Compile-time `force_ssl` cannot
be overridden at runtime — it is baked into the release binary. Inside Docker,
the simulator sends plain HTTP webhooks to Core; with force_ssl active, Core
redirects every request to HTTPS, which the simulator cannot follow (no TLS
in dev).

**Correct configuration (`config/runtime.exs`):**
```elixir
# Only enable force_ssl when FORCE_SSL=true is set (staging/prod only)
if System.get_env("FORCE_SSL") == "true" do
  config :yagye_core, YagyeCoreWeb.Endpoint, force_ssl: [hsts: true]
end
```

**Resolution:**
1. Remove `force_ssl` from `config/prod.exs` if it appears there.
2. Add the `FORCE_SSL`-gated block to `config/runtime.exs`.
3. Rebuild the Docker image with `--no-cache` (compile-time config change):
   ```bash
   docker compose build --no-cache yagye_core
   docker compose up -d yagye_core
   ```
4. Confirm: `docker logs docker-yagye_core-1 | grep force_ssl` should not appear.
   Re-test webhook delivery — payment should reach `succeeded` within ~5 seconds.

**Note:** `FORCE_SSL=true` must still be set in staging and production environments
where real HTTPS is used. The Docker dev `docker-compose.yml` must NOT set it.

---

## 11. Docker Containers Cannot Reach Each Other via `localhost`

**Symptoms:** One service (e.g. Core) cannot connect to another (e.g. Simulator
or Scoring) even though both are running. Errors show connection refused on
`localhost:PORT`. Curl from outside Docker works fine.

**Root cause:** Inside a Docker container, `localhost` refers to that container
itself, not the host machine or any sibling container. Containers communicate
using their Docker Compose **service names** as hostnames, which Docker's
internal DNS resolves to container IPs.

**Port mapping vs. container addressing:**
```
docker-compose.yml:
  yagye_simulator:
    ports:
      - "4100:4001"   ← Mac host uses localhost:4100
                        Other containers use yagye_simulator:4001
```

**Common misconfigurations and their fixes:**

| Wrong | Correct |
|---|---|
| `SCORING_SERVICE_URL=http://localhost:8001` | `http://yagye_scoring:8000` |
| `base_url: "http://localhost:4001"` (Core seeds) | `http://yagye_simulator:4001` |
| `base_url: "http://localhost:4000"` (Simulator seeds) | `http://yagye_core:4000` |

**Resolution:**
1. Use service names (not `localhost`) for all inter-container URLs in
   docker-compose env vars and in seed data.
2. Add `SCORING_SERVICE_URL: http://yagye_scoring:8000` to the `yagye_core`
   service's `environment:` block in `docker-compose.yml`.
3. Reseed with Docker service hostnames where the seed data contains URLs.
4. Restart affected containers after changing env vars.

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
