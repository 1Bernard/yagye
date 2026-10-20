# Routing Engine: Decision Tree

Last updated: 2026-10-18

```
ROUTING ENGINE: DECISION TREE
===============================
Last updated: 2026-10-18

PURPOSE: Select the correct payment provider for any payment request.
SCOPE:   Every payment dispatch. Runs synchronously before dispatch.

──────────────────────────────────────────────────────────────────────────────

RULE HIERARCHY:

  ┌─────────────────────────────────────────────────────────────────┐
  │  1. Merchant-scope rules (merchant_id = this merchant's ID)      │
  │     Evaluated FIRST. Most specific wins.                         │
  ├─────────────────────────────────────────────────────────────────┤
  │  2. Platform-scope rules (merchant_id IS NULL)                   │
  │     Evaluated if no merchant rule matches.                       │
  │     Catch-all fallbacks live here.                               │
  └─────────────────────────────────────────────────────────────────┘

  Within each scope:  ORDER BY specificity DESC, priority ASC
  Specificity = count of non-NULL filter columns on the rule.

  Example:
    Rule A: currency=GHS, method=mobile_money, network=mtn  → specificity 3
    Rule B: currency=GHS, method=mobile_money                → specificity 2
    Rule C: currency=GHS                                     → specificity 1

  For a GHS MoMo MTN payment: Rule A wins (most specific match).
  For a GHS card payment:     Rule C wins (B doesn't match method=card).

──────────────────────────────────────────────────────────────────────────────

RESOLUTION ALGORITHM:

  Given payment:
    currency     = GHS
    method       = mobile_money
    network_code = mtn
    merchant_id  = mch_018e...

  ┌────────────────────────────────────────────────────────────────────┐
  │  STEP 1: Load merchant-scope rules                                 │
  │                                                                   │
  │  SELECT * FROM routing_rules                                       │
  │  WHERE merchant_id = $merchant_id                                  │
  │    AND scope = 'merchant'                                          │
  │    AND is_active = true                                            │
  │    AND (currency IS NULL OR currency = $currency)                  │
  │    AND (payment_method_type IS NULL OR method = $method)           │
  │    AND (network_code IS NULL OR network_code = $network_code)      │
  │  ORDER BY specificity DESC, priority ASC                           │
  └───────────────────────────────────────┬────────────────────────────┘
                                          │
                              ┌───────────▼──────────────┐
                              │  Matching rules found?    │
                              └───┬────────────────────┬──┘
                                  │ YES                │ NO
                          ┌───────▼──────┐    ┌────────▼────────────────────┐
                          │ Use first    │    │  STEP 2: Load platform rules │
                          │ matching     │    │                              │
                          │ rule.        │    │  SELECT * FROM routing_rules │
                          └───────┬──────┘    │  WHERE merchant_id IS NULL   │
                                  │           │    AND scope = 'platform'    │
                                  │           │    AND is_active = true      │
                                  │           │    AND (same filters)        │
                                  │           │  ORDER BY specificity DESC,  │
                                  │           │    priority ASC              │
                                  │           └────────┬────────────────────┘
                                  │                    │
                                  │        ┌───────────▼──────────────────┐
                                  │        │  Matching rules found?        │
                                  │        └───┬──────────────────────┬───┘
                                  │            │ YES                  │ NO
                                  │    ┌───────▼──────┐   ┌──────────▼──────────┐
                                  │    │ Use first    │   │  REJECT              │
                                  │    │ platform     │   │  error: no_route_    │
                                  │    │ rule.        │   │  available           │
                                  │    └───────┬──────┘   │  HTTP 422            │
                                  │            │           └────────────────────┘
                              ┌───▼────────────▼──────────┐
                              │  SELECTED RULE:            │
                              │  provider_code = "mtn_momo_gh"
                              │  routing_configuration_id  │
                              └────────────────┬──────────┘
                                               │
                              ┌────────────────▼──────────────────────────┐
                              │  DISPATCH to provider adapter             │
                              │                                           │
                              │  MtnMomoAdapter.charge(config, params)    │
                              │                                           │
                              │  Record in payment_attempts:              │
                              │    provider_code = "mtn_momo_gh"          │
                              │    routing_configuration_id = <id>        │
                              │    idempotency_token = <our token>        │
                              └───────────────────────────────────────────┘

──────────────────────────────────────────────────────────────────────────────

ROUTING RULE EXAMPLES:

  NETWORK CONSTRAINT (MoMo):
  ─────────────────────────────────────────────────────────────────────────────
  For mobile money, the customer's MSISDN unambiguously determines the network.
  An MTN MSISDN (024x, 054x, 055x, 059x) → mtn_momo_gh ONLY.
  A Telecel/Vodafone MSISDN (020x, 050x) → vodafone_cash_gh ONLY.
  An AirtelTigo MSISDN (026x, 027x, 056x, 057x) → airteltigo_money_gh ONLY.
  There is NO cross-network fallback. MoMo rails reject cross-network charges.
  If a network rule is missing or the circuit is open → fail fast, not redirect.

  Platform rules (merchant_id IS NULL):
  ┌─────┬──────────┬────────────────┬──────────┬─────────────────┬────────────┐
  │ Pri │ Currency │ Method         │ Network  │ Provider        │ Specificity│
  ├─────┼──────────┼────────────────┼──────────┼─────────────────┼────────────┤
  │  1  │ GHS      │ mobile_money   │ mtn      │ mtn_momo_gh     │ 3 (exact)  │
  │  2  │ GHS      │ mobile_money   │ vodafone │ vodafone_cash_gh│ 3 (exact)  │
  │  3  │ GHS      │ mobile_money   │ airtl    │ airteltigo_gh   │ 3 (exact)  │
  │  4  │ USD      │ card           │ NULL     │ stripe          │ 2          │
  └─────┴──────────┴────────────────┴──────────┴─────────────────┴────────────┘

  Note: There are NO NULL-network MoMo fallbacks. For MoMo, network_code is
  always populated from MSISDN prefix detection. A NULL network means MSISDN
  detection failed — that is an error condition (reject the payment), not a
  routing ambiguity. No catch-all MoMo rules exist in the seed data.

  Merchant override (aggregator model, merchant_id = "mch_018e..."):
  ┌─────┬──────────┬────────────────┬──────────┬─────────────────┬────────────┐
  │  1  │ GHS      │ mobile_money   │ mtn      │ hubtel_mtn      │ 3          │
  │  2  │ GHS      │ mobile_money   │ vodafone │ hubtel_vodafone │ 3          │
  └─────┴──────────┴────────────────┴──────────┴─────────────────┴────────────┘

  This merchant routes through Hubtel (an aggregator) rather than direct provider
  APIs. Each rule still specifies an exact network — Hubtel_MTN handles MTN
  MSISDNs only; Hubtel_Vodafone handles Vodafone MSISDNs only. The aggregator
  abstraction does not collapse the network constraint.

──────────────────────────────────────────────────────────────────────────────

PARTIAL UNIQUE INDEXES (NULLS DISTINCT workaround):

  Problem: PostgreSQL treats two NULL values as distinct in unique indexes.
           This allows two "platform" rules with the same filters but
           NULL network_code — creating duplicate catch-all rules.

  Solution: Two separate partial indexes, each covering one scope:

  CREATE UNIQUE INDEX routing_rules_platform_unique
    ON routing_rules (scope, provider_code, payment_method_type, currency, network_code)
    WHERE merchant_id IS NULL;

  CREATE UNIQUE INDEX routing_rules_merchant_unique
    ON routing_rules (merchant_id, scope, provider_code, payment_method_type, currency, network_code)
    WHERE merchant_id IS NOT NULL;

  The platform index covers only platform rows (merchant_id IS NULL).
  Within that scope, NULL network_code IS treated as a unique value by
  the partial index — no two platform rules can have the same filters.

──────────────────────────────────────────────────────────────────────────────

REACTFLOW VISUAL BUILDER (P16+):

  Enterprise merchants build routing graphs visually in the portal.
  The graph is stored as Drawflow-serialised JSON in routing_configurations.graph_payload.
  At publish time, Core compiles the graph into routing_rules rows.

  routing_configurations
    graph_payload     jsonb   ← { nodes, edges, schema_version: 1 } (Drawflow-serialised)
    compiled_rules    jsonb   ← derived at publish time
    state             text    ← draft | published | archived
    schema_version    integer ← for future graph schema migrations

  Node vocabulary (v1 — CLOSED, no other node types):
    PaymentCondition  — filter by currency, method, network, amount range
    ProviderRoute     — route to a specific provider
    FallbackRoute     — catch-all if no preceding conditions match
    SplitRoute        — distribute across providers by percentage (A/B testing)

  The routing_configuration_id is stored on every payment_attempt as an
  immutable audit trail: "this payment was routed by configuration version X".
```
