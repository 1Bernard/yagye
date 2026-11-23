"""Tests for POST /score/recon_break."""

from fastapi.testclient import TestClient


def _payload(**overrides: object) -> dict:
    base: dict = {
        "break_id": "brk_test_001",
        "amount_delta_minor": 0,
        "expected_amount": 10_00,
        "age_hours": 48.0,
        "has_right_ref": True,
        "settlement_offset_days": 0,
    }
    return {**base, **overrides}


def test_timing_difference_zero_delta_aged(client: TestClient) -> None:
    """Zero delta, age > 24 h → timing_difference."""
    resp = client.post("/score/recon_break", json=_payload())
    assert resp.status_code == 200
    body = resp.json()
    assert body["break_id"] == "brk_test_001"
    assert body["classification"] == "timing_difference"
    assert 0.0 < body["confidence"] <= 1.0
    assert body["model_version"] == "rule_based_fallback"


def test_missing_on_right_no_provider_ref(client: TestClient) -> None:
    resp = client.post("/score/recon_break", json=_payload(
        amount_delta_minor=500_00,
        expected_amount=500_00,
        age_hours=5.0,
        has_right_ref=False,
    ))
    assert resp.status_code == 200
    body = resp.json()
    assert body["classification"] == "missing_on_right"


def test_fee_discrepancy_tiny_delta(client: TestClient) -> None:
    resp = client.post("/score/recon_break", json=_payload(
        amount_delta_minor=50,
        expected_amount=10_00,
        age_hours=2.0,
        has_right_ref=True,
    ))
    assert resp.status_code == 200
    body = resp.json()
    assert body["classification"] == "fee_discrepancy"


def test_amount_mismatch_large_delta(client: TestClient) -> None:
    resp = client.post("/score/recon_break", json=_payload(
        amount_delta_minor=500_00,
        expected_amount=500_00,
        age_hours=5.0,
        has_right_ref=True,
    ))
    assert resp.status_code == 200
    body = resp.json()
    assert body["classification"] == "amount_mismatch"


def test_response_schema(client: TestClient) -> None:
    resp = client.post("/score/recon_break", json=_payload())
    body = resp.json()
    assert set(body.keys()) == {"break_id", "classification", "confidence", "model_version"}
    assert body["classification"] in (
        "timing_difference", "fee_discrepancy", "missing_on_right", "amount_mismatch"
    )
    assert 0.0 <= body["confidence"] <= 1.0


def test_rejects_negative_expected_amount(client: TestClient) -> None:
    resp = client.post("/score/recon_break", json=_payload(expected_amount=-1))
    assert resp.status_code == 422
