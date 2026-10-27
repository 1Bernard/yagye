"""Feature fetching base — Redis cache → static fallback.

The Gold ETL (yagye_data) writes feature snapshots to Redis with a TTL.
Scoring reads them here. If Redis is unreachable or the key is stale, fall
back to static defaults that replicate current rule-based behaviour.

feature_source values:
  "realtime"        — fresh data from Redis (within feature_staleness_seconds)
  "degraded_cache"  — Redis returned data but it is stale
  "static_fallback" — Redis unreachable, key missing, or data unusable
"""

from __future__ import annotations

from typing import Any, Literal

import redis.asyncio as aioredis

FeatureSource = Literal["realtime", "degraded_cache", "static_fallback"]
FeatureResult = tuple[dict[str, Any], FeatureSource]


class FeatureClient:
    def __init__(self, redis: aioredis.Redis) -> None:  # type: ignore[type-arg]
        self._redis = redis

    async def get_json(self, key: str) -> dict[str, Any] | None:
        try:
            raw = await self._redis.get(key)
            if raw is None:
                return None
            import json

            return json.loads(raw)  # type: ignore[no-any-return]
        except Exception:
            return None
