"""Tests for POST /score/churn."""

from fastapi.testclient import TestClient


def test_churn_returns_zero_score_for_rule_based_fallback(client: TestClient) -> None:
    resp = client.post("/score/churn", json={"merchant_id": "merch_001"})
    assert resp.status_code == 200
    body = resp.json()
    assert body["merchant_id"] == "merch_001"
    assert body["churn_score"] == 0.0
    assert body["at_risk"] is False
    assert body["model_version"] == "rule_based_fallback"


def test_churn_schema(client: TestClient) -> None:
    resp = client.post("/score/churn", json={"merchant_id": "any"})
    body = resp.json()
    assert set(body.keys()) == {
        "merchant_id", "churn_score", "at_risk", "model_version", "feature_source"
    }
