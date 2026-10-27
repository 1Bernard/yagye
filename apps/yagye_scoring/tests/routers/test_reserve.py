"""Tests for POST /score/reserve."""

from fastapi.testclient import TestClient


def test_reserve_returns_default_rate(client: TestClient) -> None:
    resp = client.post("/score/reserve", json={"merchant_id": "merch_001"})
    assert resp.status_code == 200
    body = resp.json()
    assert body["merchant_id"] == "merch_001"
    assert body["recommended_rate"] == 0.05
    assert body["recommended_duration_days"] == 30
    assert body["model_version"] == "rule_based_fallback"
    assert body["feature_source"] == "static_fallback"


def test_reserve_rate_within_bounds(client: TestClient) -> None:
    resp = client.post("/score/reserve", json={"merchant_id": "any"})
    body = resp.json()
    assert 0.0 <= body["recommended_rate"] <= 1.0
