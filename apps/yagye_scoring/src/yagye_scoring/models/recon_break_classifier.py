"""Reconciliation break classifier — gradient-boosted classifier (multi-class).

Classifies a detected reconciliation break into one of four root-cause categories
that map directly onto the ReconciliationBreak schema's @valid_classifications:

  timing_difference  — amount matches; break is a settlement-delay artefact
  fee_discrepancy    — small delta attributable to fee rounding / markup
  missing_on_right   — payment absent from the provider's settlement report
                       (typically a lost webhook or delayed settlement file)
  amount_mismatch    — genuine shortfall or overpayment

Rule-based fallback encodes the same decision tree the ML model learns from
labelled breaks once enough data accumulates post-P22.
"""

from __future__ import annotations

from typing import Any, Literal

import numpy as np

from yagye_scoring.models.base import BaseMLModel
from yagye_scoring.shared.logging import get_logger

logger = get_logger(__name__)

BreakClass = Literal[
    "timing_difference",
    "fee_discrepancy",
    "missing_on_right",
    "amount_mismatch",
]

_RECON_FEATURES = [
    "amount_delta_minor",        # expected - actual (may be negative for overpayment)
    "abs_delta_minor",           # |expected - actual|
    "relative_delta",            # abs_delta / expected (capped at 1.0)
    "age_hours",                 # hours since break was detected
    "has_right_ref",             # 1.0 if provider ref present, else 0.0
    "settlement_offset_days",    # days between expected and actual settlement date
]

_DEFAULTS: dict[str, float] = {
    "amount_delta_minor": 0.0,
    "abs_delta_minor": 0.0,
    "relative_delta": 0.0,
    "age_hours": 0.0,
    "has_right_ref": 0.0,
    "settlement_offset_days": 0.0,
}

# Class index → label (must match training label encoding)
_CLASSES: list[BreakClass] = [
    "timing_difference",
    "fee_discrepancy",
    "missing_on_right",
    "amount_mismatch",
]

# Small fee delta threshold: up to 1 GHS in pesewas, 1 USD in cents, etc.
_FEE_DELTA_THRESHOLD = 100


class ReconBreakClassifier(BaseMLModel):
    """Multi-class classifier for reconciliation break root-cause."""

    def _build_feature_vector(self, features: dict[str, Any]) -> np.ndarray:
        row = [float(features.get(f, _DEFAULTS[f])) for f in _RECON_FEATURES]
        return np.array([row], dtype=np.float32)

    def rule_based_predict(self, features: dict[str, Any]) -> float:
        """Returns the class index as a float; callers should use classify_break()."""
        return float(self._rule_based_class_index(features))

    def classify_break(
        self, features: dict[str, Any]
    ) -> tuple[BreakClass, float]:
        """Return (classification, confidence) using ONNX model or rule-based fallback."""
        if self.is_loaded:
            try:
                vec = self._build_feature_vector(features)
                output = self._session.run(None, {self._input_name: vec})
                # LightGBM ONNX: output[0] = class label (int64), output[1] = list of dicts
                # {class_index: probability} for each sample
                raw_probs = output[1][0]  # dict: {0: p0, 1: p1, 2: p2, 3: p3}
                if isinstance(raw_probs, dict):
                    probs_arr = np.array([raw_probs.get(i, 0.0) for i in range(len(_CLASSES))], dtype=np.float32)
                else:
                    probs_arr = np.asarray(raw_probs, dtype=np.float32)
                class_idx = int(np.argmax(probs_arr))
                confidence = float(probs_arr[class_idx])
                return _CLASSES[class_idx], confidence
            except Exception as exc:
                logger.warning(
                    "onnx_inference_failed_falling_back",
                    model=self.model_name,
                    error=str(exc),
                )
        class_idx = self._rule_based_class_index(features)
        confidence = self._rule_based_confidence(features, class_idx)
        return _CLASSES[class_idx], confidence

    def _rule_based_class_index(self, features: dict[str, Any]) -> int:
        abs_delta = float(features.get("abs_delta_minor", 0.0))
        age_hours = float(features.get("age_hours", 0.0))
        has_right_ref = float(features.get("has_right_ref", 0.0))

        # Zero-delta break that aged past 24 h → settlement delay
        if abs_delta == 0 and age_hours > 24:
            return 0  # timing_difference

        # Provider ref present but small amount delta → fee rounding
        if abs_delta > 0 and abs_delta <= _FEE_DELTA_THRESHOLD and has_right_ref == 1.0:
            return 1  # fee_discrepancy

        # No provider reference at all → missing from provider report
        if has_right_ref == 0.0:
            return 2  # missing_on_right

        # Everything else → genuine amount mismatch
        return 3  # amount_mismatch

    def _rule_based_confidence(self, features: dict[str, Any], class_idx: int) -> float:
        """Heuristic confidence for the rule-based path."""
        abs_delta = float(features.get("abs_delta_minor", 0.0))
        age_hours = float(features.get("age_hours", 0.0))

        if class_idx == 0:  # timing_difference: more confident the older the break
            return min(0.60 + (age_hours / 168) * 0.30, 0.90)
        if class_idx == 1:  # fee_discrepancy: very confident when delta is tiny
            return 0.80 if abs_delta <= _FEE_DELTA_THRESHOLD // 2 else 0.65
        if class_idx == 2:  # missing_on_right: rule is unambiguous
            return 0.75
        return 0.55  # amount_mismatch: least certain from rules alone
