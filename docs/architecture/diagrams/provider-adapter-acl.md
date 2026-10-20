# Provider Adapter Pattern (ACL)

Last updated: 2026-10-18

```
PROVIDER ADAPTER PATTERN (ANTI-CORRUPTION LAYER)
==================================================
Last updated: 2026-10-18

PURPOSE: Show how Yagye's provider adapter isolates Core from
         provider-specific HTTP APIs, authentication, and webhook formats.
         The adapter is an ACL (Anti-Corruption Layer) in DDD terminology.

──────────────────────────────────────────────────────────────────────────────

THE PROBLEM WITHOUT AN ACL:

  Without abstraction, provider-specific details leak everywhere:

  PaymentController → calls MTN MoMo API directly
    → if MTN changes their API, every call site changes
    → adding Stripe requires finding all MTN-specific code
    → testing requires a real MTN sandbox or complex mocking
    → error codes are provider-specific strings scattered in business logic

  The ACL prevents this. Core speaks one internal language.
  Adapters translate between Core's language and each provider's language.

──────────────────────────────────────────────────────────────────────────────

THE ADAPTER CONTRACT:

  Every provider adapter implements exactly five callbacks:

  @callback charge(provider_config, payment_params, opts) ::
    {:ok, ProviderResponse.t()} | {:error, ProviderError.t()}

  @callback void(provider_config, payment_attempt, opts) ::
    {:ok, VoidResponse.t()} | {:error, ProviderError.t()}

  @callback refund(provider_config, payment, refund_params, opts) ::
    {:ok, RefundResponse.t()} | {:error, ProviderError.t()}

  @callback verify_webhook(provider_config, headers, raw_body) ::
    :ok | {:error, :invalid_signature}

  @callback parse_webhook(provider_config, headers, body) ::
    {:ok, WebhookEvent.t()} | {:error, :unknown_event_type}

  Core calls these. Core never knows what HTTP headers MTN requires,
  what field names Stripe uses, or how Flutterwave signs its webhooks.

──────────────────────────────────────────────────────────────────────────────

ADAPTER RESOLUTION:

  ┌─────────────────────────────────────────────────────────────────────┐
  │  Routing rule selected: provider_code = "mtn_momo_gh"               │
  └──────────────────────────────────────┬──────────────────────────────┘
                                         │
                      ┌──────────────────▼────────────────────────────────┐
  mode = simulation?  │  Yagye.Providers.resolve(provider_code, mode)      │
    → GatewaySimulator│  Returns the adapter MODULE for this provider+mode │
  mode = sandbox?     └──────────────────┬────────────────────────────────┘
    → MtnMomoAdapter      (sandbox config)│
  mode = live?                           │
    → MtnMomoAdapter      (live config)  ▼
                      ┌──────────────────────────────────────────────────┐
                      │  adapter.charge(provider_config, payment_params) │
                      │  Translates Core's payment_params into provider's │
                      │  request format                                  │
                      └──────────────────┬──────────────────────────────┘
                                         │
              ┌──────────────────────────▼─────────────────────────────────┐
              │  PROVIDER-SPECIFIC TRANSLATION (inside the adapter)         │
              │                                                            │
              │  MtnMomoAdapter.charge/3:                                  │
              │    POST /v1_0/requesttopay                                  │
              │    Headers:                                                 │
              │      Authorization: Bearer <momo_token>                    │
              │      X-Reference-Id: <idempotency_token>                   │
              │      X-Target-Environment: sandbox                         │
              │    Body:                                                    │
              │      { "amount": "97.50",        ← string, not integer     │
              │        "currency": "GHS",                                   │
              │        "externalId": "<token>",                            │
              │        "payer": { "partyIdType": "MSISDN",                 │
              │                   "partyId": "024100..." } }               │
              └──────────────────┬─────────────────────────────────────────┘
                                 │
                   ┌─────────────▼────────────────────────────────────────┐
                   │  Response translated to Core's internal type:          │
                   │                                                       │
                   │  {:ok, %ProviderResponse{                             │
                   │    external_reference: "mtn-ref-abc123",              │
                   │    status: :pending,                                  │
                   │    raw_response: %{...}  ← kept for audit             │
                   │  }}                                                   │
                   └──────────────────────────────────────────────────────┘

──────────────────────────────────────────────────────────────────────────────

WEBHOOK INGESTION (verify + parse):

  POST /provider-webhooks/mtn_momo_gh
       │
       ▼
  controller calls:
    adapter = resolve("mtn_momo_gh", conn.assigns.mode)
       │
       ▼
  adapter.verify_webhook(config, conn.req_headers, raw_body)
    MtnMomoAdapter: HMAC-SHA256(secret, raw_body) vs X-Callback-Token
    StripeAdapter:  Stripe-Signature header, timestamp tolerance check
    GatewaySimulator: always :ok (no real signature in dev)
       │
       ▼
  {:ok} → adapter.parse_webhook(config, headers, body)
    Translates provider webhook format to Core's WebhookEvent struct:
    %WebhookEvent{
      event_type: "payment.completed",     ← Core's vocabulary
      external_reference: "mtn-ref-abc123",
      status: :succeeded,
      amount: 10_000,                      ← already in minor units
      currency: "GHS",
      ...
    }
       │
       ▼
  Core processes WebhookEvent in provider-agnostic business logic
  (update payment_attempt, write ledger, publish outbox)

──────────────────────────────────────────────────────────────────────────────

THE GATEWAY SIMULATOR AS DEV ACL:

  In development and CI, provider_code resolution maps ALL providers
  to the GatewaySimulator, regardless of which provider was selected.

  GatewaySimulator speaks the SAME HTTP protocol as real providers:
    - Real TCP connections on localhost
    - Real HTTP headers and JSON bodies
    - Req.post/2 is called — not mocked at the HTTP level

  This tests Core's adapter code without sandbox credentials.

  Outcome control (deterministic):
    MSISDN 024 100 0001 → charge succeeds
    MSISDN 024 100 0002 → insufficient_funds
    MSISDN 024 100 0003 → timeout (no response for 30s)
    MSISDN 024 100 0004 → provider error (503)
    X-Simulator-Outcome: success / fail / timeout / partial_refund

  GatewaySimulator is STATELESS:
    No SQLite persistence needed.
    Each request is handled independently.
    Simplicity over fidelity for the aspects that don't need state.

──────────────────────────────────────────────────────────────────────────────

TESTING STRATEGY (three tiers):

  Tier 1: Req.Test unit tests (run in CI)
    Test the adapter's request construction and response parsing.
    Req.Test stubs HTTP at the library level.
    Fast, no network, no sandbox credentials required.
    48 tests across all adapters (as of 2026-09-25).

  Tier 2: Gateway simulator integration (run in CI)
    End-to-end dispatch via real HTTP.
    Real Ecto transactions, real Oban jobs.
    No real provider credentials.

  Tier 3: Provider sandbox integration (manual, pre-release)
    Real sandbox credentials.
    ngrok tunnel for webhook delivery to localhost.
    Not run in automated CI — too slow, requires secrets.

──────────────────────────────────────────────────────────────────────────────

ADDING A NEW PROVIDER:

  1. Implement the 5-callback behaviour module in:
     lib/yagye_core/providers/adapters/new_provider_adapter.ex

  2. Add provider_credentials seed data for sandbox and live configs.

  3. Add routing_rules rows pointing to the new provider_code.

  4. Write Req.Test unit tests for charge/void/refund/verify/parse.

  5. Add MSISDN → outcome mappings to gateway_simulator (for dev/CI).

  No changes required in Core's business logic (PaymentDispatchWorker,
  ReconciliationWorker, etc.) — they are provider-agnostic by design.
```
