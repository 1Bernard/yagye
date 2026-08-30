# Domain Glossary

Terms used consistently across the codebase, API contracts, and internal
communication. When a term appears in code (module names, function names,
column names) it maps to the definition here.

---

## Core Business Terms

**Merchant**
A business that has signed up to use Yagye as its payment service provider.
A merchant has a `merchant_code` (short human-readable identifier) and a UUID
`id`. Merchants go through a KYB (Know Your Business) process before they can
process live payments.

**Customer**
An end user (person) who pays a merchant. Customers are identified by the
merchant's own reference (`merchant_customer_ref`) — Yagye does not own the
customer relationship, the merchant does. Customers are created automatically
on first payment (`find_or_create`).

**Payment**
A single charge attempt by a customer to a merchant. A payment has one or more
attempts (retries) and a lifecycle: `pending → processing → succeeded | failed`.
A payment is immutable once in a terminal state; it is never deleted.

**Payment Attempt**
A single call to a downstream payment provider for a given payment. A payment
may have multiple attempts if the first fails and a retry is dispatched to a
different provider. The attempt records the provider's reference and response.

**Provider**
A downstream payment network or gateway that Yagye connects to: MTN MoMo,
Vodafone Cash, AirtelTigo, Stripe, Flutterwave, Paystack. Each provider has
a `code` (e.g. `mtn_momo`, `stripe`) and one or more `ProviderCredential`
records per merchant.

**MoMo (Mobile Money)**
Mobile money payments in Ghana: MTN MoMo, Vodafone Cash (now Telecel Cash),
AirtelTigo Money. Payments are made by MSISDN (phone number). The network is
determined from the MSISDN prefix.

**MSISDN**
Mobile Station International Subscriber Directory Number — a phone number in
international format (e.g. `+233241000001`). The primary customer identifier
for MoMo payments.

**Settlement**
The process of Yagye remitting collected funds to the merchant. A settlement
covers a time window and a provider, netting fees against gross receipts.
Settlement lifecycle: `expected → reported → matched | mismatched → disbursed`.

**Settlement Batch**
A grouping of settlement items for a given merchant, currency, and period.
Batches are created by the settlement engine and transitioned through states.

**Ledger / Double-Entry Ledger**
Yagye maintains a double-entry ledger (ADR-0005) for all money movements.
Every financial event produces a balanced set of `ledger_postings` — debits
and credits that sum to zero. The ledger is the authoritative record of money;
the `payments` table is the transactional record of what happened.

**Float**
Yagye's pooled funds held in mobile money wallets and bank accounts. When a
customer pays via MoMo, the money lands in Yagye's MoMo float before being
settled to the merchant. The float balance is tracked per-network per-currency.

**Reserve**
A portion of a merchant's funds withheld by Yagye as collateral against
chargebacks and disputes. Released over a rolling window.

**Routing Rule**
A configurable rule that determines which provider handles a payment, based on
conditions (amount, currency, network, customer risk tier, etc.). Rules have a
scope (`platform` = Yagye-managed; `merchant` = enterprise override) and a
priority. Lower priority integer = higher precedence.

**Invoice**
A payment request from a merchant to a customer, with line items, tax, due
date, and a state machine: `draft → open → paid | void`. Invoices are
identified by a `public_id` (`inv_…`) and a human-readable `number`.

**KYB (Know Your Business)**
The compliance process for onboarding a merchant: identity verification,
beneficial owner disclosure, document collection, AML screening. Managed by
the `Compliance` context in Core and the compliance queue in the portal.

**KYC (Know Your Customer)**
The process of verifying a customer's identity, typically via a name enquiry
against the telco or bank. Results in a `kyc_tier` on the customer record.

**KYC Tier**
`tier_1` (unverified) | `tier_2` (name-matched) | `tier_3` (fully verified).
Tier determines transaction limits enforced by `VelocityChecker`.

**Velocity Limit**
A per-customer and per-merchant ceiling on single-transaction amount, daily
total, and monthly total. Enforced before payment dispatch. Configurable per
risk tier and payment method.

**Dispute**
A customer or bank challenge against a completed payment. Lifecycle:
`submitted → under_review → won | lost`. Won disputes result in a refund.

**Refund**
A reversal of part or all of a payment, initiated by the merchant. Distinct
from a dispute: a refund is merchant-initiated; a dispute is third-party-
initiated.

**Payout**
A disbursement of funds from Yagye to a merchant's bank account or mobile
wallet. Distinct from settlement: a settlement is the internal accounting;
a payout is the actual funds transfer.

**Outbox**
The transactional outbox pattern (ADR-0014). Domain events are written to
`outbox_messages` in the same DB transaction as the domain change, then
relayed to consumers (portal via Redpanda, webhooks via Oban) asynchronously.

**Projection / Read Model**
A denormalised, query-optimised view of domain data, updated by processing
outbox events. Examples: `proj_merchant_balances`, `proj_payment_summaries`.
Projections are eventually consistent with the write model.

**Mode**
`simulation` | `sandbox` | `live`. All domain records carry a `mode` field.
Simulation is local/test; sandbox calls real provider sandboxes; live processes
real money. Mode is determined per-merchant at payment creation time.

**Public ID**
The externally-visible identifier for a domain entity, in the format
`prefix_<uuidv7>` (e.g. `pay_018e…`). Never the internal UUID `id`. See
ADR-0007.

**Idempotency Key**
A client-supplied header (`Idempotency-Key`) that allows safe retries of
mutating API calls. If the same key is submitted twice, the second call returns
the cached response from the first. Keys expire after 24 hours. See ADR-0008.

---

## Acronyms

| Acronym | Meaning |
|---|---|
| AML | Anti-Money Laundering |
| DLX | Dead Letter Exchange (RabbitMQ) |
| FK | Foreign Key |
| KYB | Know Your Business |
| KYC | Know Your Customer |
| MoMo | Mobile Money |
| MSISDN | Mobile Station International Subscriber Directory Number |
| PCI-DSS | Payment Card Industry Data Security Standard |
| PSP | Payment Service Provider |
| RBAC | Role-Based Access Control |
| SoD | Segregation of Duties |
| TOTP | Time-Based One-Time Password |
| UBO | Ultimate Beneficial Owner |
