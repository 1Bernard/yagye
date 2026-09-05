# ADR-0024: Agentic Finance API Surface

**Date:** 2026-09-05
**Status:** Proposed

---

## Context

AI agents (e.g. Raverpay's Nkem) are autonomous API clients that move real
money on behalf of end-users. They introduce failure modes that traditional
merchant integrations do not:

- **Hallucination retries** — an LLM tool loop may call `POST /v1/payments`
  multiple times for the same intent.
- **Prompt injection / drain attacks** — a malicious prompt may attempt to
  transfer all funds or initiate hundreds of rapid transactions.
- **Asynchronous MoMo flows** — an agent cannot block a thread waiting for
  a USSD callback; it must be notified via webhook.

Yagye's existing idempotency layer (ADR-0008), velocity guardrails, and
outbox webhooks already solve these problems at the infrastructure level.
What is missing is the API surface that lets an agent authenticate and
act on behalf of a specific end-user rather than a merchant-level API key.

---

## Decision

### Gap 1 — Customer-scoped delegation tokens

Add a `customer_tokens` table scoped to `(merchant_id, customer_id)`.
A merchant issues a short-lived token for a specific customer session.
The token permits a restricted set of operations (pay, check balance, list
transactions) and is bound by the merchant's own velocity limits.

This is additive — no changes to existing merchant auth. Agents use the
customer token; merchant backend systems use `sk_live_...` as today.

### Gap 2 — `customer_wallets` ledger account type

Add a `customer_wallet` account type to the Core ledger. A customer wallet
is a first-class ledger account (debit/credit tracked immutably) anchored to
a `(merchant_id, customer_reference)` pair.

This enables neobank-style store-of-value use cases where an agent manages
a persistent balance for a WhatsApp user, distinct from a pass-through
payment.

Posting rules: same double-entry invariant as all other account types.
`customer_wallet → float_account` on load; `customer_wallet → merchant_payable`
on withdrawal.

### Gap 3 — Stablecoin provider adapter

A stablecoin rail (USDC/USDT via Yellow Card, Bridge, or BVNK) is modelled
as a standard `ProviderAdapter` — the same behaviour interface used by MTN
MoMo, Stripe, and Flutterwave adapters. The ledger gets a `stablecoin_float`
account type. Settlement and reconciliation apply unchanged.

This is intentionally deferred to post-P22 (requires a banking relationship
and regulatory sign-off on crypto rails). The decision is recorded here so
that no architectural choice before P22 closes the door on it.

### What Yagye does NOT build

Yagye does not build a WhatsApp bot, an AI agent, or a consumer-facing
financial assistant. The agentic API surface is B2B infrastructure — the
same positioning as the rest of the platform. Agents like Nkem are customers
of Yagye, not products Yagye ships.

---

## Consequences

- Customer-scoped tokens (Gap 1) can be added in a P13 extension — small
  surface area, high leverage for agentic partners.
- Customer wallets (Gap 2) require a ledger migration and new account type
  registration — scope to P16 or later.
- Stablecoin adapter (Gap 3) is post-P22, gated on regulatory approval.
- The OpenAPI spec (`/api/openapi`) already makes Yagye's endpoints machine-
  readable — generating LLM function-calling schemas from the spec requires
  no additional code.
