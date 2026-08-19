# OpenAPI Contracts

This directory contains the versioned OpenAPI specifications for each Yagye service.

| File | Service | Generated from |
|------|---------|----------------|
| [yagye-core.json](yagye-core.json) | `yagye_core` (Elixir/Phoenix) | `GET /api/openapi` |

## Updating

The spec is generated at runtime by OpenApiSpex from the router and schema modules.
To refresh the contract after adding or changing endpoints:

```bash
cd apps/yagye_core
mix phx.server          # ensure server is running
curl -s http://localhost:4000/api/openapi | python3 -m json.tool --indent 2 \
  > ../../contracts/openapi/yagye-core.json
```

Commit the updated file alongside the code change that produced it so the
contract stays in sync with the implementation.

## Status

- `yagye-core.json` — Phase 1 (merchants, API keys, compliance onboarding)
- `yagye-portal.json` — not yet generated (Portal is Rails; Rswag to be configured)
- `gateway-simulator.json` — not yet generated
