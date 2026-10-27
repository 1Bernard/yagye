"""Tests for POST /score/routing."""

from fastapi.testclient import TestClient


def test_routing_single_candidate_returns_go_hold(client: TestClient) -> None:
    payload = {
        "payment_id": "pay_001",
        "provider_candidates": [
            {"provider_code": "mtn_momo_gh", "provider_kind": "native_rail"}
        ],
        "payment_method": "mobile_money",
        "network_code": "MTN",
        "amount_minor": 5000,
        "hour_of_day": 14,
        "day_of_week": 1,
    }
    resp = client.post("/score/routing", json=payload)
    assert resp.status_code == 200
    body = resp.json()
    assert body["payment_id"] == "pay_001"
    assert body["routing_mode"] == "go_hold"
    assert len(body["provider_scores"]) == 1
    assert body["provider_scores"][0]["provider_code"] == "mtn_momo_gh"
    assert 0.0 <= body["provider_scores"][0]["score"] <= 1.0
    assert body["model_version"] == "rule_based_fallback"
    assert body["feature_source"] == "static_fallback"


def test_routing_multiple_candidates_returns_provider_selection(client: TestClient) -> None:
    payload = {
        "payment_id": "pay_002",
        "provider_candidates": [
            {"provider_code": "stripe_gh", "provider_kind": "external_psp"},
            {"provider_code": "paystack_gh", "provider_kind": "external_psp"},
        ],
        "payment_method": "card",
        "network_code": None,
        "amount_minor": 100000,
        "hour_of_day": 10,
        "day_of_week": 3,
    }
    resp = client.post("/score/routing", json=payload)
    assert resp.status_code == 200
    body = resp.json()
    assert body["routing_mode"] == "provider_selection"
    assert len(body["provider_scores"]) == 2
    # Scores must be sorted descending
    scores = [s["score"] for s in body["provider_scores"]]
    assert scores == sorted(scores, reverse=True)


def test_routing_scores_above_threshold_by_default(client: TestClient) -> None:
    """Rule-based fallback returns 0.85 (static default) which is above the 0.60 threshold."""
    payload = {
        "payment_id": "pay_003",
        "provider_candidates": [
            {"provider_code": "vodafone_cash_gh", "provider_kind": "native_rail"}
        ],
        "payment_method": "mobile_money",
        "network_code": "Telecel",
        "amount_minor": 10000,
        "hour_of_day": 8,
        "day_of_week": 0,
    }
    resp = client.post("/score/routing", json=payload)
    assert resp.status_code == 200
    body = resp.json()
    # Rule-based score = 0.85 which is above threshold 0.60 → go_hold (not hold_all)
    assert body["routing_mode"] == "go_hold"


def test_routing_rejects_empty_candidates(client: TestClient) -> None:
    payload = {
        "payment_id": "pay_004",
        "provider_candidates": [],
        "payment_method": "mobile_money",
        "network_code": "MTN",
        "amount_minor": 5000,
        "hour_of_day": 9,
        "day_of_week": 2,
    }
    resp = client.post("/score/routing", json=payload)
    assert resp.status_code == 422


def test_routing_mixed_kinds_uses_external_psp_model(client: TestClient) -> None:
    """Mixed native_rail + external_psp list falls through to external_psp model."""
    payload = {
        "payment_id": "pay_005",
        "provider_candidates": [
            {"provider_code": "mtn_momo_gh", "provider_kind": "native_rail"},
            {"provider_code": "hubtel_mtn_gh", "provider_kind": "external_psp"},
        ],
        "payment_method": "mobile_money",
        "network_code": "MTN",
        "amount_minor": 20000,
        "hour_of_day": 16,
        "day_of_week": 4,
    }
    resp = client.post("/score/routing", json=payload)
    assert resp.status_code == 200
    body = resp.json()
    assert body["routing_mode"] == "provider_selection"
