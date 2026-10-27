"""Merchant risk feature fetching.

Redis key schema (written by Gold ETL — merchant_features_weekly):
  yagye:features:merchant:{merchant_id}
  → {
      "monthly_volume_ghs": float,
      "chargeback_rate_30d": float,
      "chargeback_rate_90d": float,
      "chargeback_rate_180d": float,
      "dispute_rate_90d": float,
      "settlement_failure_count_90d": int,
      "avg_payment_amount": float,
      "payment_amount_std": float,
      "merchant_sector": str,
      "merchant_kyb_tier": str,
      "merchant_age_days": int,
      "peak_volume_ratio": float,
      "updated_at": ISO8601 string
    }
"""

from __future__ import annotations

from typing import Any

from yagye_scoring.features.base import FeatureClient, FeatureResult, FeatureSource
from yagye_scoring.features.provider_health import _check_staleness

_STATIC_DEFAULTS: dict[str, Any] = {
    "monthly_volume_ghs": 0.0,
    "chargeback_rate_30d": 0.0,
    "chargeback_rate_90d": 0.0,
    "chargeback_rate_180d": 0.0,
    "dispute_rate_90d": 0.0,
    "settlement_failure_count_90d": 0.0,
    "avg_payment_amount": 0.0,
    "payment_amount_std": 0.0,
    "merchant_sector_enc": 0.0,
    "merchant_kyb_tier_enc": 0.0,
    "merchant_age_days": 0.0,
    "peak_volume_ratio": 1.0,
}


async def get_merchant_features(merchant_id: str, client: FeatureClient) -> FeatureResult:
    key = f"yagye:features:merchant:{merchant_id}"
    data = await client.get_json(key)

    if data is None:
        return _STATIC_DEFAULTS.copy(), "static_fallback"

    source: FeatureSource = _check_staleness(data)

    return {
        "monthly_volume_ghs": data.get("monthly_volume_ghs", 0.0),
        "chargeback_rate_30d": data.get("chargeback_rate_30d", 0.0),
        "chargeback_rate_90d": data.get("chargeback_rate_90d", 0.0),
        "chargeback_rate_180d": data.get("chargeback_rate_180d", 0.0),
        "dispute_rate_90d": data.get("dispute_rate_90d", 0.0),
        "settlement_failure_count_90d": data.get("settlement_failure_count_90d", 0.0),
        "avg_payment_amount": data.get("avg_payment_amount", 0.0),
        "payment_amount_std": data.get("payment_amount_std", 0.0),
        "merchant_sector_enc": 0.0,  # OrdinalEncoder applied at inference time post-P22
        "merchant_kyb_tier_enc": 0.0,
        "merchant_age_days": float(data.get("merchant_age_days", 0)),
        "peak_volume_ratio": data.get("peak_volume_ratio", 1.0),
    }, source
