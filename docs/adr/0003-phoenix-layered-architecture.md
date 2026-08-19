# ADR-0003: Phoenix Two-Layer Architecture (core / web)

**Date:** 2026-08-17
**Status:** Accepted

## Context

`mix phx.new` generates two logical layers in one OTP application:

- `YagyeCore` (`lib/yagye_core/`) — business logic, contexts, schemas, repo
- `YagyeCoreWeb` (`lib/yagye_core_web/`) — controllers, router, plugs, endpoint

The question is whether to enforce a strict dependency direction between them,
or treat them as a flat set of modules that can call each other freely.

Without an explicit rule, controllers drift into containing business logic, and
context functions drift into returning HTTP-shaped responses. Both directions
make the core harder to test and harder to reason about.

## Decision

**`YagyeCoreWeb` may call `YagyeCore`. `YagyeCore` must never call `YagyeCoreWeb`.**

Concretely:
- Controllers are thin: they parse params, call one context function, and render
  the result. No business logic lives in a controller.
- Context functions in `YagyeCore` return domain values or `{:ok, _} | {:error, _}`
  tuples. They have no knowledge of HTTP status codes, JSON shapes, or plug assigns.
- Plugs that implement cross-cutting concerns (e.g. `CorrelationId`) live in
  `YagyeCoreWeb.Plugs` and may only read/write Plug.Conn state.

## Consequences

### Positive
- The entire `YagyeCore` layer can be tested without starting the HTTP server:
  `DataCase` and plain `ExUnit.Case` tests cover all business logic.
- Business logic is portable — if a background job or a LiveView needs the same
  operation as a REST controller, it calls the same context function.
- Onboarding is clear: a new developer knows which layer to look in for any given
  concern.

### Negative / Trade-offs
- Controllers cannot shortcut — even a trivially simple endpoint must go through
  the context layer. This is more code for read-only passthrough operations.

### Implementation note (added Phase 1)
The boundary is enforced **statically at compile time** via the
[`boundary`](https://hex.pm/packages/boundary) library. `lib/yagye_core.ex`
declares `use Boundary, exports: [...]` listing every struct the web layer is
permitted to reference. Any call that crosses the boundary without an explicit
export produces a compiler warning. The P8 Credo check is no longer needed.
