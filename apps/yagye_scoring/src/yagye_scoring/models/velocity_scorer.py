"""Velocity & burst anomaly scorer — IsolationForest (unsupervised).

Detects unusual transaction velocity patterns for a customer MSISDN hash.
Rule-based fallback uses three heuristics that mirror what an IsolationForest
learns from normal traffic:
  1. Burst — many attempts in the last hour
  2. Failure flood — high recent failure count
  3. High failure rate over 24 h

Score is in [0, 1]; higher = more anomalous.
Threshold (is_anomaly) is set at 0.65 by convention — same as the IsolationForest
contamination parameter used at training time.
"""

from __future__ import annotations

from typing import Any

import numpy as np

from yagye_scoring.models.base import BaseMLModel
from yagye_scoring.shared.logging import get_logger

logger = get_logger(__name__)

_VELOCITY_FEATURES = [
    "attempt_count_1h",
    "fail_count_1h",
    "txn_count_24h",
    "failure_rate",
    "distinct_merchant_count",
    "amount_minor",
    "is_momo",
    "hour_of_day",
    "day_of_week",
]

_DEFAULTS: dict[str, float] = {
    "attempt_count_1h": 0.0,
    "fail_count_1h": 0.0,
    "txn_count_24h": 0.0,
    "failure_rate": 0.0,
    "distinct_merchant_count": 1.0,
    "amount_minor": 0.0,
    "is_momo": 1.0,
    "hour_of_day": 12.0,
    "day_of_week": 0.0,
}

ANOMALY_THRESHOLD = 0.65


class VelocityScorer(BaseMLModel):
    """IsolationForest-backed velocity anomaly scorer."""

    def _build_feature_vector(self, features: dict[str, Any]) -> np.ndarray:
        row = [float(features.get(f, _DEFAULTS[f])) for f in _VELOCITY_FEATURES]
        return np.array([row], dtype=np.float32)

    def rule_based_predict(self, features: dict[str, Any]) -> float:
        attempt_1h = float(features.get("attempt_count_1h", 0))
        fail_1h = float(features.get("fail_count_1h", 0))
        failure_rate = float(features.get("failure_rate", 0.0))

        # Burst: >= 10 attempts in 1 h is highly anomalous
        if attempt_1h >= 10:
            return 0.90

        # Failure flood: 5+ failures in 1 h
        if fail_1h >= 5:
            return 0.78

        # High sustained failure rate over 24 h
        if failure_rate >= 0.70:
            return 0.68

        # Elevated but not extreme activity
        if attempt_1h >= 5:
            return 0.45

        return 0.10

    def predict(self, features: dict[str, Any]) -> float:
        """Return anomaly score in [0, 1]; applies sigmoid to IsolationForest output."""
        if self.is_loaded:
            try:
                x = self._build_feature_vector(features)
                raw = self._run_onnx(x)  # IsolationForest decision_function: lower = more anomalous
                # decision_function is negative for anomalies; sigmoid maps it to (0.5, 1]
                return float(1.0 / (1.0 + np.exp(raw)))
            except Exception as exc:
                logger.warning(
                    "onnx_inference_failed_falling_back",
                    model=self.model_name,
                    error=str(exc),
                )
        return self.rule_based_predict(features)
