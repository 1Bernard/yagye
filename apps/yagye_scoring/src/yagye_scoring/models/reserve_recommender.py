"""Reserve recommender — XGBoost regression.

Predicts the optimal rolling reserve rate for a merchant.
Rule-based fallback: return the configured default rate (5%).
The ops team reviews recommendations before applying them — no automated changes.
"""

from __future__ import annotations

from typing import Any

import numpy as np

from yagye_scoring.models.base import BaseMLModel

_RESERVE_FEATURES = [
    "monthly_volume_ghs",
    "chargeback_rate_90d",
    "chargeback_rate_180d",
    "dispute_rate_90d",
    "settlement_failure_count_90d",
    "merchant_sector_enc",
    "merchant_kyb_tier_enc",
    "merchant_age_days",
    "avg_payment_amount",
    "payment_amount_std",
    "peak_volume_ratio",
]

_DEFAULTS: dict[str, float] = {
    "monthly_volume_ghs": 0.0,
    "chargeback_rate_90d": 0.0,
    "chargeback_rate_180d": 0.0,
    "dispute_rate_90d": 0.0,
    "settlement_failure_count_90d": 0.0,
    "merchant_sector_enc": 0.0,
    "merchant_kyb_tier_enc": 0.0,
    "merchant_age_days": 0.0,
    "avg_payment_amount": 0.0,
    "payment_amount_std": 0.0,
    "peak_volume_ratio": 1.0,
}


class ReserveRecommender(BaseMLModel):
    def __init__(self, model_name: str, default_rate: float = 0.05) -> None:
        super().__init__(model_name)
        self._default_rate = default_rate

    def _build_feature_vector(self, features: dict[str, Any]) -> np.ndarray:
        row = [float(features.get(f, _DEFAULTS[f])) for f in _RESERVE_FEATURES]
        return np.array([row], dtype=np.float32)

    def rule_based_predict(self, features: dict[str, Any]) -> float:
        return self._default_rate

    def predict_reserve(self, features: dict[str, Any]) -> tuple[float, int]:
        """Return (rate, duration_days). Duration defaults to 30d."""
        rate = self.predict(features)
        # Clamp to reasonable range
        rate = max(0.01, min(rate, 0.25))
        return rate, 30
