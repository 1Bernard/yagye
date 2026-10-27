"""Tests for training/gate.py.

Uses synthetic ONNX models built from sklearn RandomForest (fast to train,
no GPU required) to avoid the XGBoost dependency in CI.  The gate logic
itself is independent of the model type — it just needs ONNX bytes.

All S3 calls are mocked so no Floci / AWS credentials are needed.
"""

from __future__ import annotations

import io
from unittest.mock import MagicMock, patch

import numpy as np
import pytest

try:
    from sklearn.datasets import make_classification
    from sklearn.ensemble import RandomForestClassifier

    from yagye_data.training.gate import _MIN_IMPROVEMENT, _score_onnx_bytes, should_promote

    TRAINING_DEPS_AVAILABLE = True
except ImportError:
    TRAINING_DEPS_AVAILABLE = False

pytestmark = pytest.mark.skipif(
    not TRAINING_DEPS_AVAILABLE,
    reason="training optional-dependencies not installed",
)


# ── Helpers ───────────────────────────────────────────────────────────────────


def _make_onnx_bytes(n_features: int = 6, n_estimators: int = 5) -> bytes:
    """Train a tiny sklearn RF and export to ONNX bytes."""
    from skl2onnx import to_onnx
    from skl2onnx.common.data_types import FloatTensorType

    X, y = make_classification(
        n_samples=200, n_features=n_features, n_informative=3, n_redundant=2, random_state=42
    )
    clf = RandomForestClassifier(n_estimators=n_estimators, random_state=42)
    clf.fit(X.astype(np.float32), y)

    onnx_model = to_onnx(
        clf,
        X[:1].astype(np.float32),
        initial_types=[("X", FloatTensorType([None, n_features]))],
    )
    return onnx_model.SerializeToString()


def _make_val_data(n_features: int = 6) -> tuple[np.ndarray, np.ndarray]:
    X, y = make_classification(
        n_samples=100, n_features=n_features, n_informative=3, n_redundant=2, random_state=0
    )
    return X.astype(np.float32), y.astype(np.int64)


# ── _score_onnx_bytes ─────────────────────────────────────────────────────────


def test_score_onnx_bytes_returns_float_in_range() -> None:
    X_val, y_val = _make_val_data()
    model_bytes = _make_onnx_bytes()
    score = _score_onnx_bytes(model_bytes, X_val, y_val)
    assert isinstance(score, float)
    assert 0.0 <= score <= 1.0


def test_score_onnx_bytes_uses_aucpr_not_auc_roc() -> None:
    """The gate score must be AUCPR (average_precision_score), not AUC-ROC."""
    from sklearn.metrics import average_precision_score, roc_auc_score
    import onnxruntime as ort

    X_val, y_val = _make_val_data()
    model_bytes = _make_onnx_bytes()

    gate_score = _score_onnx_bytes(model_bytes, X_val, y_val)

    sess = ort.InferenceSession(model_bytes)
    input_name = sess.get_inputs()[0].name
    probs = sess.run(None, {input_name: X_val.astype(np.float32)})[1]
    raw_scores = np.array([p.get(1, 0.0) for p in probs])

    aucpr = average_precision_score(y_val, raw_scores)
    auc_roc = roc_auc_score(y_val, raw_scores)

    assert abs(gate_score - aucpr) < 1e-6, "gate must use AUCPR"
    # On balanced synthetic data these may be close, but the function must
    # specifically match AUCPR, not AUC-ROC
    assert gate_score == pytest.approx(aucpr, abs=1e-6)
    assert gate_score != pytest.approx(auc_roc, abs=1e-6) or aucpr == pytest.approx(auc_roc, abs=1e-6)


# ── should_promote — no champion ──────────────────────────────────────────────


def test_should_promote_returns_true_when_no_champion() -> None:
    X_val, y_val = _make_val_data()
    challenger_bytes = _make_onnx_bytes()

    class FakeOnnxModel:
        def SerializeToString(self) -> bytes:
            return challenger_bytes

    with patch("yagye_data.training.gate._fetch_champion", return_value=None):
        result = should_promote("routing_predictor", FakeOnnxModel(), X_val, y_val)

    assert result is True


# ── should_promote — challenger beats champion ────────────────────────────────


def test_should_promote_returns_true_when_challenger_is_better() -> None:
    from sklearn.datasets import make_classification
    from skl2onnx import to_onnx
    from skl2onnx.common.data_types import FloatTensorType
    from sklearn.ensemble import RandomForestClassifier

    n_features = 6
    X, y = make_classification(
        n_samples=300, n_features=n_features, n_informative=3, n_redundant=2, random_state=42
    )
    X = X.astype(np.float32)

    # Weak champion: RF trained on permuted labels → near-random predictions
    y_shuffled = np.random.default_rng(0).permutation(y[:200])
    weak_rf = RandomForestClassifier(n_estimators=3, max_depth=1, random_state=0)
    weak_rf.fit(X[:200], y_shuffled)
    champion_onnx = to_onnx(
        weak_rf,
        X[:1],
        initial_types=[("X", FloatTensorType([None, n_features]))],
    )
    champion_bytes = champion_onnx.SerializeToString()

    # Strong challenger: RF trained on correct labels
    rf = RandomForestClassifier(n_estimators=20, random_state=42)
    rf.fit(X[:200], y[:200])
    challenger_onnx = to_onnx(
        rf,
        X[:1],
        initial_types=[("X", FloatTensorType([None, n_features]))],
    )

    X_val, y_val = X[200:].astype(np.float32), y[200:].astype(np.int64)

    class FakeOnnxModel:
        def SerializeToString(self) -> bytes:
            return challenger_onnx.SerializeToString()

    with patch("yagye_data.training.gate._fetch_champion", return_value=champion_bytes):
        result = should_promote(
            "routing_predictor",
            FakeOnnxModel(),
            X_val,
            y_val,
            min_improvement=0.0,  # any improvement counts
        )

    assert result is True


def test_should_promote_returns_false_when_champion_holds() -> None:
    """If challenger == champion, no improvement → champion holds."""
    X_val, y_val = _make_val_data()
    model_bytes = _make_onnx_bytes()

    class FakeOnnxModel:
        def SerializeToString(self) -> bytes:
            return model_bytes

    # Champion and challenger are the SAME model — delta = 0
    with patch("yagye_data.training.gate._fetch_champion", return_value=model_bytes):
        result = should_promote(
            "routing_predictor",
            FakeOnnxModel(),
            X_val,
            y_val,
            min_improvement=_MIN_IMPROVEMENT,  # 0.005 — same model can't beat itself
        )

    # Delta is ~0; with min_improvement > 0, champion holds
    assert result is False


# ── _fetch_champion versioned path ────────────────────────────────────────────


def test_fetch_champion_reads_versioned_path() -> None:
    from yagye_data.training.gate import _fetch_champion

    fake_model_bytes = b"fake_onnx_bytes"
    mock_s3 = MagicMock()

    def get_object_side_effect(Bucket: str, Key: str) -> dict:
        if Key == "routing_predictor/champion.flag":
            return {"Body": io.BytesIO(b"v20261027_120000")}
        if Key == "routing_predictor/v20261027_120000/model.onnx":
            return {"Body": io.BytesIO(fake_model_bytes)}
        raise Exception(f"Unexpected key: {Key}")

    mock_s3.get_object.side_effect = get_object_side_effect

    with patch("yagye_data.training.gate.get_s3_client", return_value=mock_s3):
        result = _fetch_champion("routing_predictor")

    assert result == fake_model_bytes


def test_fetch_champion_falls_back_to_flat_path_when_no_flag() -> None:
    from yagye_data.training.gate import _fetch_champion

    fake_model_bytes = b"old_flat_model"
    mock_s3 = MagicMock()

    def get_object_side_effect(Bucket: str, Key: str) -> dict:
        if Key == "routing_predictor/champion.flag":
            raise Exception("NoSuchKey")
        if Key == "routing_predictor/model.onnx":
            return {"Body": io.BytesIO(fake_model_bytes)}
        raise Exception(f"Unexpected key: {Key}")

    mock_s3.get_object.side_effect = get_object_side_effect

    with patch("yagye_data.training.gate.get_s3_client", return_value=mock_s3):
        result = _fetch_champion("routing_predictor")

    assert result == fake_model_bytes


def test_fetch_champion_returns_none_when_s3_completely_absent() -> None:
    from yagye_data.training.gate import _fetch_champion

    mock_s3 = MagicMock()
    mock_s3.get_object.side_effect = Exception("S3 unreachable")

    with patch("yagye_data.training.gate.get_s3_client", return_value=mock_s3):
        result = _fetch_champion("routing_predictor")

    assert result is None
