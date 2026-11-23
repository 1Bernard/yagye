"""Unit tests for ReconBreakClassifier rule-based fallback."""

import pytest

from yagye_scoring.models.recon_break_classifier import ReconBreakClassifier


@pytest.fixture()
def clf() -> ReconBreakClassifier:
    return ReconBreakClassifier("recon_break_classifier")


def test_timing_difference_zero_delta_aged_break(clf: ReconBreakClassifier) -> None:
    classification, confidence = clf.classify_break({
        "amount_delta_minor": 0,
        "abs_delta_minor": 0,
        "relative_delta": 0.0,
        "age_hours": 48.0,
        "has_right_ref": 1.0,
        "settlement_offset_days": 0.0,
    })
    assert classification == "timing_difference"
    assert confidence > 0.60


def test_fee_discrepancy_tiny_delta_with_provider_ref(clf: ReconBreakClassifier) -> None:
    classification, confidence = clf.classify_break({
        "amount_delta_minor": 50,
        "abs_delta_minor": 50,
        "relative_delta": 0.005,
        "age_hours": 2.0,
        "has_right_ref": 1.0,
        "settlement_offset_days": 0.0,
    })
    assert classification == "fee_discrepancy"
    assert confidence >= 0.65


def test_missing_on_right_no_provider_ref(clf: ReconBreakClassifier) -> None:
    classification, confidence = clf.classify_break({
        "amount_delta_minor": 10_00,
        "abs_delta_minor": 10_00,
        "relative_delta": 0.1,
        "age_hours": 5.0,
        "has_right_ref": 0.0,
        "settlement_offset_days": 2.0,
    })
    assert classification == "missing_on_right"
    assert confidence >= 0.70


def test_amount_mismatch_large_delta_provider_ref_present(clf: ReconBreakClassifier) -> None:
    classification, confidence = clf.classify_break({
        "amount_delta_minor": 500_00,
        "abs_delta_minor": 500_00,
        "relative_delta": 0.5,
        "age_hours": 10.0,
        "has_right_ref": 1.0,
        "settlement_offset_days": 0.0,
    })
    assert classification == "amount_mismatch"


def test_model_not_loaded(clf: ReconBreakClassifier) -> None:
    assert not clf.is_loaded
    assert clf.version == "rule_based_fallback"


def test_timing_difference_confidence_increases_with_age(clf: ReconBreakClassifier) -> None:
    _, conf_young = clf.classify_break({
        "amount_delta_minor": 0, "abs_delta_minor": 0, "relative_delta": 0.0,
        "age_hours": 25.0, "has_right_ref": 1.0, "settlement_offset_days": 0.0,
    })
    _, conf_old = clf.classify_break({
        "amount_delta_minor": 0, "abs_delta_minor": 0, "relative_delta": 0.0,
        "age_hours": 150.0, "has_right_ref": 1.0, "settlement_offset_days": 0.0,
    })
    assert conf_old > conf_young


def test_zero_delta_fresh_break_not_timing_difference(clf: ReconBreakClassifier) -> None:
    """Zero delta but age < 24 h → not yet timing_difference; falls to missing_on_right."""
    classification, _ = clf.classify_break({
        "amount_delta_minor": 0, "abs_delta_minor": 0, "relative_delta": 0.0,
        "age_hours": 10.0, "has_right_ref": 0.0, "settlement_offset_days": 0.0,
    })
    assert classification == "missing_on_right"
