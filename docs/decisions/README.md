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
