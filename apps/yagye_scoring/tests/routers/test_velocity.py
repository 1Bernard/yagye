"""Tests for POST /score/velocity."""

import pytest
from fastapi.testclient import TestClient


def _payload(**overrides: object) -> dict:
    base: dict = {
        "payment_id": "pay_vel_001",
        "msisdn_hash": "deadbeef1234",
        "merchant_id": "merch_001",
        "amount_minor": 10_00,
        "payment_method": "mobile_money",
        "hour_of_day": 10,
        "day_of_week": 1,
    }
    return {**base, **overrides}


def test_velocity_low_activity_returns_not_anomaly(client: TestClient) -> None:
    """NullFeatureClient returns None → static_fallback with low score → not anomaly."""
    resp = client.post("/score/velocity", json=_payload())
    assert resp.status_code == 200
    body = resp.json()
    assert body["payment_id"] == "pay_vel_001"
    assert body["anomaly_score"] == pytest.approx(0.10, abs=1e-6)
    assert body["is_anomaly"] is False
    assert body["model_version"] == "rule_based_fallback"
    assert body["feature_source"] == "static_fallback"


def test_velocity_response_schema(client: TestClient) -> None:
    resp = client.post("/score/velocity", json=_payload())
    body = resp.json()
    assert set(body.keys()) == {
        "payment_id", "anomaly_score", "is_anomaly", "model_version", "feature_source"
    }
    assert 0.0 <= body["anomaly_score"] <= 1.0
    assert isinstance(body["is_anomaly"], bool)


def test_velocity_card_payment_accepted(client: TestClient) -> None:
    resp = client.post("/score/velocity", json=_payload(payment_method="card"))
    assert resp.status_code == 200


def test_velocity_rejects_invalid_hour(client: TestClient) -> None:
    resp = client.post("/score/velocity", json=_payload(hour_of_day=25))
    assert resp.status_code == 422


def test_velocity_rejects_negative_amount(client: TestClient) -> None:
    resp = client.post("/score/velocity", json=_payload(amount_minor=-1))
    assert resp.status_code == 422


def test_velocity_rejects_invalid_day(client: TestClient) -> None:
    resp = client.post("/score/velocity", json=_payload(day_of_week=7))
    assert resp.status_code == 422
