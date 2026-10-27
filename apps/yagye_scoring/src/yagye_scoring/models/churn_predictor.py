"""Merchant churn predictor — XGBoost binary classifier.

Predicts P(merchant reduces volume > 50% or closes account within 30 days).
Rule-based fallback: return 0.0 (no merchants flagged) so the review queue
stays empty until real training data exists.
"""

from __future__ import annotations

from typing import Any

import numpy as np

from yagye_scoring.models.base import BaseMLModel

_CHURN_FEATURES = [
    "volume_trend_90d",
    "volume_week_over_week",
    "active_days_30d",
    "success_rate_30d",
    "api_error_rate_30d",
    "failed_webhook_count_30d",
    "last_login_days_ago",
    "merchant_age_days",
    "merchant_sector_enc",
    "has_active_dispute",
    "pricing_change_30d",
]

_DEFAULTS: dict[str, float] = {
    "volume_trend_90d": 0.0,
    "volume_week_over_week": 0.0,
    "active_days_30d": 30.0,
    "success_rate_30d": 0.85,
    "api_error_rate_30d": 0.0,
    "failed_webhook_count_30d": 0.0,
    "last_login_days_ago": 0.0,
    "merchant_age_days": 0.0,
    "merchant_sector_enc": 0.0,
    "has_active_dispute": 0.0,
    "pricing_change_30d": 0.0,
}


class ChurnPredictor(BaseMLModel):
    def _build_feature_vector(self, features: dict[str, Any]) -> np.ndarray:
        row = [float(features.get(f, _DEFAULTS[f])) for f in _CHURN_FEATURES]
        return np.array([row], dtype=np.float32)

    def rule_based_predict(self, features: dict[str, Any]) -> float:
        return 0.0
