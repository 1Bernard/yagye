"""Shared test fixtures.

Tests run without Redis and without ONNX models. The registry is pre-built
with all models in rule-based fallback mode (is_loaded=False) and a mock
FeatureClient that returns static defaults for every key.
"""

from __future__ import annotations

from typing import Any
from unittest.mock import AsyncMock

import pytest
from fastapi.testclient import TestClient

from yagye_scoring.features.base import FeatureClient
from yagye_scoring.main import app
from yagye_scoring.models.churn_predictor import ChurnPredictor
from yagye_scoring.models.reserve_recommender import ReserveRecommender
from yagye_scoring.models.risk_scorer import RiskScorer
from yagye_scoring.models.routing_predictor import RoutingPredictor
from yagye_scoring.registry import ModelRegistry


class NullFeatureClient(FeatureClient):
    """Returns None for every key — forces static_fallback in all feature modules."""

    def __init__(self) -> None:
        pass  # no redis

    async def get_json(self, key: str) -> dict[str, Any] | None:
        return None


def make_test_registry() -> ModelRegistry:
    native = RoutingPredictor("routing_native_rail")
    external = RoutingPredictor("routing_external_psp")
    risk = RiskScorer("risk_scorer")
    reserve = ReserveRecommender("reserve_recommender", default_rate=0.05)
    churn = ChurnPredictor("churn_predictor")
    client = NullFeatureClient()

    redis_mock = AsyncMock()
    redis_mock.ping = AsyncMock(return_value=True)

    return ModelRegistry(
        routing_native_rail=native,
        routing_external_psp=external,
        risk_scorer=risk,
        reserve_recommender=reserve,
        churn_predictor=churn,
        feature_client=client,
        _redis=redis_mock,
    )


@pytest.fixture()
def client() -> TestClient:
    registry = make_test_registry()
    app.state.registry = registry
    return TestClient(app, raise_server_exceptions=True)
