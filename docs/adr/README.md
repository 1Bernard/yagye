# Architecture Decision Records

This directory contains Architecture Decision Records (ADRs) for Yagye.

An ADR captures a significant architectural decision: the context that drove it,
what was decided, and the consequences — both the benefits we gain and the
trade-offs we accept. ADRs are never deleted; superseded decisions are marked
as such and point to the newer record.

## Format

```markdown
# ADR-NNNN: Title

**Date:** YYYY-MM-DD
**Status:** Accepted | Proposed | Deprecated | Superseded by ADR-XXXX

## Context

What situation forced this decision? What constraints, goals, or prior
decisions made certain choices impossible or undesirable?

## Decision

What did we decide? One clear statement.

## Consequences

### Positive
- ...

### Negative / Trade-offs
- ...
```

## Index

| # | Title | Status |
|---|-------|--------|
| [0001](0001-poncho-monorepo.md) | Poncho monorepo over umbrella or separate repos | Accepted |
| [0002](0002-integer-minor-units.md) | Integer minor units for monetary values | Accepted |
| [0003](0003-phoenix-layered-architecture.md) | Phoenix two-layer architecture (core / web) | Accepted |
| [0004](0004-structured-json-logging.md) | Structured JSON logging via logger_json | Accepted |
| [0005](0005-double-entry-ledger.md) | Double-entry ledger as the accounting model | Accepted |
| [0006](0006-postgresql-as-system-of-record.md) | PostgreSQL as the system of record | Accepted |
| [0007](0007-prefixed-uuidv7-public-ids.md) | Prefixed UUIDv7 as public IDs | Accepted |
| [0008](0008-db-backed-idempotency.md) | PostgreSQL-backed idempotency state machine | Accepted |
| [0009](0009-soft-revocation-no-hard-delete.md) | Soft revocation — no hard deletes for credentials | Accepted |
| [0010](0010-stripe-style-error-envelope.md) | Stripe-style JSON error envelope | Accepted |
| [0011](0011-bearer-auth-mode-aware-api-keys.md) | Bearer token auth with mode-aware API keys | Accepted |
| [0012](0012-oban-for-background-jobs.md) | Oban for background job processing | Accepted |
| [0013](0013-gateway-simulator-as-acl.md) | Permanent gateway simulator as the anti-corruption layer | Accepted |
| [0014](0014-transactional-outbox.md) | Transactional outbox for domain event emission | Accepted |
| [0015](0015-outbox-driven-projections.md) | Outbox-driven read-model projections | Accepted |
| [0016](0016-portal-phlex-view-layer.md) | Portal view layer: Phlex components | Accepted |
| [0017](0017-portal-dynamic-rbac.md) | Portal dynamic DB-backed RBAC | Accepted |
| [0018](0018-ui-theme-single-source.md) | UI theme as a single-source token system | Accepted |
| [0019](0019-cursor-keyset-pagination.md) | Cursor-based keyset pagination for all list endpoints | Accepted |
| [0020](0020-restrict-fk-no-hard-delete-psp.md) | RESTRICT foreign keys — no hard deletes for PSP data | Accepted |
| [0021](0021-dual-scope-routing-rules.md) | Dual-scope routing rules (platform + merchant) | Accepted |
