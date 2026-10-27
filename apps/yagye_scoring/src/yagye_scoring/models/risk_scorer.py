"""Risk scorer — LightGBM binary classifier.

Predicts P(chargeback) for a payment attempt.
Rule-based fallback: return 0.1 (low risk) so payments flow normally during
the shadow period. Velocity limits in Core remain the active risk backstop.
"""

from __future__ import annotations

from typing import Any

import numpy as np

from yagye_scoring.models.base import BaseMLModel

_RISK_FEATURES = [
    "amount_minor",
    "amount_z_score",
    "customer_attempt_count_1h",
    "customer_fail_count_1h",
    "customer_distinct_merchants_1h",
    "customer_amount_total_1h",
    "customer_kyc_tier_enc",
    "merchant_chargeback_rate_30d",
    "merchant_sector_enc",
    "hour_of_day",
    "day_of_week",
    "is_new_customer",
    "is_new_msisdn_for_merchant",
]

_DEFAULTS: dict[str, float] = {
    "amount_minor": 0.0,
    "amount_z_score": 0.0,
    "customer_attempt_count_1h": 0.0,
    "customer_fail_count_1h": 0.0,
    "customer_distinct_merchants_1h": 1.0,
    "customer_amount_total_1h": 0.0,
    "customer_kyc_tier_enc": 0.0,
    "merchant_chargeback_rate_30d": 0.0,
    "merchant_sector_enc": 0.0,
    "hour_of_day": 12.0,
    "day_of_week": 0.0,
    "is_new_customer": 0.0,
    "is_new_msisdn_for_merchant": 0.0,
}


class RiskScorer(BaseMLModel):
    def _build_feature_vector(self, features: dict[str, Any]) -> np.ndarray:
        row = [float(features.get(f, _DEFAULTS[f])) for f in _RISK_FEATURES]
        return np.array([row], dtype=np.float32)

    def rule_based_predict(self, features: dict[str, Any]) -> float:
        # Conservative fallback: allow all payments, rely on velocity limits.
        return 0.1
