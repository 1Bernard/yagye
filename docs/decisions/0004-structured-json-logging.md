# ADR-0004: Structured JSON Logging via logger_json

**Date:** 2026-08-17
**Status:** Accepted

## Context

Yagye will run on AWS (ECS tasks behind an ALB). Logs are shipped to CloudWatch
Logs and queried via CloudWatch Insights or forwarded to a log aggregation tool.

Two logging approaches were considered:

**Option A — Default Elixir Logger (plain text)**: zero configuration. Produces
human-readable lines like `[info] GET /api/v1/payments`. Not machine-parseable;
CloudWatch Insights cannot filter or aggregate fields without fragile regex.

**Option B — Structured JSON logging**: every log line is a JSON object with
consistent keys (`level`, `message`, `timestamp`, `request_id`, etc.).
CloudWatch Insights can query `fields @message | filter level = "error"` and
aggregate by any key without parsing.

For Option B, two libraries exist in the Elixir ecosystem:
- `logger_json` — uses OTP's new `:logger` handler system (`:default_handler` +
  formatter callback). Actively maintained, supports OTP 26+.
- `ink` — older approach using the traditional `:logger` backend system.

## Decision

We use **`logger_json ~> 7.0`** with `LoggerJSON.Formatters.Basic` as the
`:default_handler` formatter. A custom plug (`YagyeCoreWeb.Plugs.CorrelationId`)
reads the `x-request-id` response header set by `Plug.RequestId` and writes it
into `Logger.metadata(request_id: value)` so every log line emitted during a
request carries the request's correlation ID.

## Consequences

### Positive
- Every log line is a parseable JSON object; no regex required in CloudWatch Insights.
- `request_id` threads through every log line for a given HTTP request, making it
  trivial to reconstruct the full log trail for a single transaction.
- `logger_json` uses the OTP `:default_handler` system — the modern approach for
  OTP 26+. It composes cleanly with Elixir's `Logger` module.

### Negative / Trade-offs
- `logger_json` configures logging through `:default_handler`, not through the
  traditional `config :logger, metadata: [...]` key. Credo's
  `MissedMetadataKeyInLoggerConfig` check raises a false positive because it only
  understands the old format. The check is disabled in `.credo.exs` with an
  explanatory comment.
- Log output is not human-readable in development without a JSON pretty-printer
  (`mix phx.server | jq`). A dev-only formatter can be configured in `config/dev.exs`
  if this becomes friction.
- The `CorrelationId` plug must appear in the pipeline **after** `Plug.RequestId`
  sets the response header, or `request_id` will be nil.
