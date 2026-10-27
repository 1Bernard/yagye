"""Tests for POST /score/risk."""

from fastapi.testclient import TestClient


def _payload(**overrides: object) -> dict:
    base: dict = {
        "payment_id": "pay_risk_001",
        "merchant_id": "merch_001",
        "customer_msisdn_hash": "abc123hash",
        "amount_minor": 10000,
        "hour_of_day": 14,
        "day_of_week": 1,
        "customer_kyc_tier": 1,
        "is_new_customer": False,
        "is_new_msisdn_for_merchant": False,
    }
    return {**base, **overrides}


def test_risk_returns_allow_for_rule_based_fallback(client: TestClient) -> None:
    """Rule-based fallback returns 0.1 → decision=allow."""
    resp = client.post("/score/risk", json=_payload())
    assert resp.status_code == 200
    body = resp.json()
    assert body["payment_id"] == "pay_risk_001"
    assert body["risk_score"] == pytest.approx(0.1, abs=1e-6)
    assert body["decision"] == "allow"
    assert body["model_version"] == "rule_based_fallback"
    assert body["feature_source"] == "static_fallback"


def test_risk_response_schema(client: TestClient) -> None:
    resp = client.post("/score/risk", json=_payload())
    body = resp.json()
    assert set(body.keys()) == {
        "payment_id", "risk_score", "decision", "model_version", "feature_source"
    }
    assert 0.0 <= body["risk_score"] <= 1.0
    assert body["decision"] in ("allow", "review", "block")


def test_risk_rejects_invalid_kyc_tier(client: TestClient) -> None:
    resp = client.post("/score/risk", json=_payload(customer_kyc_tier=5))
    assert resp.status_code == 422


import pytest
