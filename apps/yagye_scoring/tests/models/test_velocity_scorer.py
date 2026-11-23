"""Unit tests for VelocityScorer rule-based fallback."""

import pytest

from yagye_scoring.models.velocity_scorer import ANOMALY_THRESHOLD, VelocityScorer


@pytest.fixture()
def scorer() -> VelocityScorer:
    return VelocityScorer("velocity_scorer")


def test_rule_based_low_activity_returns_low_score(scorer: VelocityScorer) -> None:
    score = scorer.predict({
        "attempt_count_1h": 1,
        "fail_count_1h": 0,
        "failure_rate": 0.0,
        "txn_count_24h": 3,
        "distinct_merchant_count": 1,
        "amount_minor": 10_00,
        "is_momo": 1.0,
        "hour_of_day": 10.0,
        "day_of_week": 1.0,
    })
    assert score == pytest.approx(0.10, abs=1e-6)
    assert not (score >= ANOMALY_THRESHOLD)


def test_burst_10_attempts_triggers_anomaly(scorer: VelocityScorer) -> None:
    score = scorer.predict({
        "attempt_count_1h": 10,
        "fail_count_1h": 0,
        "failure_rate": 0.0,
    })
    assert score >= ANOMALY_THRESHOLD
    assert score == pytest.approx(0.90, abs=1e-6)


def test_failure_flood_5_fails_triggers_anomaly(scorer: VelocityScorer) -> None:
    score = scorer.predict({
        "attempt_count_1h": 6,
        "fail_count_1h": 5,
        "failure_rate": 0.0,
    })
    assert score >= ANOMALY_THRESHOLD
    assert score == pytest.approx(0.78, abs=1e-6)


def test_high_failure_rate_triggers_anomaly(scorer: VelocityScorer) -> None:
    score = scorer.predict({
        "attempt_count_1h": 3,
        "fail_count_1h": 2,
        "failure_rate": 0.75,
    })
    assert score >= ANOMALY_THRESHOLD
    assert score == pytest.approx(0.68, abs=1e-6)


def test_elevated_but_subthreshold_returns_mid_score(scorer: VelocityScorer) -> None:
    score = scorer.predict({
        "attempt_count_1h": 7,
        "fail_count_1h": 1,
        "failure_rate": 0.14,
    })
    assert score == pytest.approx(0.45, abs=1e-6)
    assert score < ANOMALY_THRESHOLD


def test_missing_features_use_defaults(scorer: VelocityScorer) -> None:
    # Completely empty features dict — should not raise
    score = scorer.predict({})
    assert 0.0 <= score <= 1.0


def test_model_not_loaded(scorer: VelocityScorer) -> None:
    assert not scorer.is_loaded
    assert scorer.version == "rule_based_fallback"


def test_burst_wins_over_failure_rate(scorer: VelocityScorer) -> None:
    """Burst check comes first; a burst of 10 wins even if failure_rate is also high."""
    score = scorer.predict({
        "attempt_count_1h": 10,
        "fail_count_1h": 0,
        "failure_rate": 0.80,
    })
    assert score == pytest.approx(0.90, abs=1e-6)
