"""Routing health predictor — two model instances.

routing_native_rail  → Model A merchants (single aggregator path per network).
                        Optimises the go/hold decision.
routing_external_psp → Model B merchants (multiple PSP candidates).
                        Optimises provider selection across PSPs.

Rule-based fallback: use recent_success_rate_1h as the score proxy.
This mirrors what Core's circuit breaker already does (health-based routing)
and ensures shadow mode produces a fair baseline comparison.
"""

from __future__ import annotations

from typing import Any

import numpy as np

from yagye_scoring.models.base import BaseMLModel

# Feature columns in training order — must match the ONNX input schema exactly.
# Changing this list is a MAJOR version bump on the model.
_ROUTING_FEATURES = [
    "provider_code_enc",
    "provider_kind_enc",
    "payment_method_enc",
    "network_code_enc",
    "amount_bucket",
    "hour_of_day",
    "day_of_week",
    "recent_success_rate_1h",
    "recent_success_rate_24h",
    "avg_latency_ms_1h",
    "circuit_breaker_state",
    "candidate_count",
]

_DEFAULTS: dict[str, float] = {
    "provider_code_enc": -1.0,
    "provider_kind_enc": 0.0,
    "payment_method_enc": 0.0,
    "network_code_enc": -1.0,
    "amount_bucket": 0.0,
    "hour_of_day": 12.0,
    "day_of_week": 0.0,
    "recent_success_rate_1h": 0.85,
    "recent_success_rate_24h": 0.85,
    "avg_latency_ms_1h": 2000.0,
    "circuit_breaker_state": 0.0,
    "candidate_count": 1.0,
}


class RoutingPredictor(BaseMLModel):
    def _build_feature_vector(self, features: dict[str, Any]) -> np.ndarray:
        row = [float(features.get(f, _DEFAULTS[f])) for f in _ROUTING_FEATURES]
        return np.array([row], dtype=np.float32)

    def rule_based_predict(self, features: dict[str, Any]) -> float:
        # Shadow-mode baseline: replicate Core's health-based static routing.
        # Higher recent success rate → prefer this provider.
        return float(features.get("recent_success_rate_1h", _DEFAULTS["recent_success_rate_1h"]))


def make_routing_models() -> tuple[RoutingPredictor, RoutingPredictor]:
    """Return (native_rail_model, external_psp_model) — both unloaded at P20."""
    return RoutingPredictor("routing_native_rail"), RoutingPredictor("routing_external_psp")
