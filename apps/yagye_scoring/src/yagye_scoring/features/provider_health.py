"""Provider health feature fetching.

Redis key schema (written by Gold ETL):
  yagye:features:provider:{provider_code}
  → {
      "success_rate_1h": float,
      "success_rate_24h": float,
      "avg_latency_ms_1h": float,
      "circuit_breaker_state": int (0=closed, 1=half_open, 2=open),
      "updated_at": ISO8601 string
    }
"""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

from yagye_scoring.config import settings
from yagye_scoring.features.base import FeatureClient, FeatureResult, FeatureSource
from yagye_scoring.shared.logging import get_logger

logger = get_logger(__name__)

_STATIC_DEFAULTS: dict[str, Any] = {
    "recent_success_rate_1h": 0.85,
    "recent_success_rate_24h": 0.85,
    "avg_latency_ms_1h": 2000.0,
    "circuit_breaker_state": 0,
}


async def get_provider_features(
    provider_codes: list[str],
    client: FeatureClient,
) -> tuple[dict[str, dict[str, Any]], FeatureSource]:
    """Fetch health features for a list of providers.

    Returns ({provider_code: feature_dict}, feature_source).
    If any provider fails, its entry uses static defaults and source is degraded.
    """
    results: dict[str, dict[str, Any]] = {}
    worst_source: FeatureSource = "realtime"

    for code in provider_codes:
        features, source = await _fetch_one(code, client)
        results[code] = features
        if source == "static_fallback":
            worst_source = "static_fallback"
        elif source == "degraded_cache" and worst_source == "realtime":
            worst_source = "degraded_cache"

    return results, worst_source


async def _fetch_one(provider_code: str, client: FeatureClient) -> FeatureResult:
    key = f"yagye:features:provider:{provider_code}"
    data = await client.get_json(key)

    if data is None:
        return _STATIC_DEFAULTS.copy(), "static_fallback"

    source: FeatureSource = _check_staleness(data)

    return {
        "recent_success_rate_1h": data.get("success_rate_1h", _STATIC_DEFAULTS["recent_success_rate_1h"]),
        "recent_success_rate_24h": data.get("success_rate_24h", _STATIC_DEFAULTS["recent_success_rate_24h"]),
        "avg_latency_ms_1h": data.get("avg_latency_ms_1h", _STATIC_DEFAULTS["avg_latency_ms_1h"]),
        "circuit_breaker_state": data.get("circuit_breaker_state", 0),
    }, source


def _check_staleness(data: dict[str, Any]) -> FeatureSource:
    updated_at_raw = data.get("updated_at")
    if not updated_at_raw:
        return "degraded_cache"
    try:
        updated_at = datetime.fromisoformat(updated_at_raw).replace(tzinfo=UTC)
        age_seconds = (datetime.now(UTC) - updated_at).total_seconds()
        if age_seconds > settings.feature_staleness_seconds:
            return "degraded_cache"
        return "realtime"
    except ValueError:
        return "degraded_cache"
