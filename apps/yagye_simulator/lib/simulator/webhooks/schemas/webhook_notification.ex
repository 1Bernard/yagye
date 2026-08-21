# TODO(p6): Webhook notification schema — deferred to P6 (Inbound Webhooks & Asynchrony)
#
# Purpose: represents the signed payload the simulator POSTs to yagye_core after an
# async outcome is determined (e.g. mobile money wallet prompt approved/rejected).
#
# Flow this enables:
#   1. yagye_core sends POST /charges → simulator returns state: PENDING_AUTH
#   2. Simulator enqueues a WebhookDeliveryWorker (Oban job, configurable delay_ms)
#   3. Worker POSTs a signed WebhookNotification to yagye_core's inbound webhook endpoint
#   4. yagye_core's inbox processes it, transitions the payment to succeeded/failed
#
# Fields to define here:
#   - charge_ref       (links back to the charge)
#   - event_type       ("charge.succeeded" | "charge.failed" | "charge.timed_out")
#   - outcome          (maps to Simulator.OutcomeEngine result)
#   - auth_code        (present on success)
#   - decline_code     (present on failure)
#   - occurred_at      (domain timestamp of the outcome)
#   - signature        (HMAC-SHA256 of the payload, key from account.webhook_secret)
#
# Related:
#   - lib/simulator/webhooks/webhook_delivery_worker.ex  (Oban worker, also TODO)
#   - lib/simulator/charges/charges.ex                   (enqueues the worker on create)
#   - yagye_core inbound webhook handler                 (the receiver, built in P6)
