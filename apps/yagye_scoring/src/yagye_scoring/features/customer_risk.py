"""Customer risk feature fetching.

Redis key schema (written by Gold ETL — risk_features_hourly):
  yagye:features:customer:{customer_msisdn_hash}
  → {
      "attempt_count_1h": int,
      "fail_count_1h": int,
      "distinct_merchants_1h": int,
      "amount_total_1h": int,
      "updated_at": ISO8601 string
    }
"""

from __future__ import annotations

from typing import Any

from yagye_scoring.features.base import FeatureClient, FeatureResult, FeatureSource
from yagye_scoring.features.provider_health import _check_staleness

_STATIC_DEFAULTS: dict[str, Any] = {
    "customer_attempt_count_1h": 0.0,
    "customer_fail_count_1h": 0.0,
    "customer_distinct_merchants_1h": 1.0,
    "customer_amount_total_1h": 0.0,
}


async def get_customer_features(
    customer_msisdn_hash: str, client: FeatureClient
) -> FeatureResult:
    key = f"yagye:features:customer:{customer_msisdn_hash}"
    data = await client.get_json(key)

    if data is None:
        return _STATIC_DEFAULTS.copy(), "static_fallback"

    source: FeatureSource = _check_staleness(data)

    return {
        "customer_attempt_count_1h": float(data.get("attempt_count_1h", 0)),
        "customer_fail_count_1h": float(data.get("fail_count_1h", 0)),
        "customer_distinct_merchants_1h": float(data.get("distinct_merchants_1h", 1)),
        "customer_amount_total_1h": float(data.get("amount_total_1h", 0)),
    }, source
