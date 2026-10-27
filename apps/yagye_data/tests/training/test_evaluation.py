"""Tests for training/evaluation.py.

Uses synthetic data only — no S3, no DuckDB, no external dependencies beyond
the training extras (sklearn, xgboost, matplotlib).

The SHAP beeswarm and MLflow logging paths are exercised inside an in-memory
MLflow run so they run without a server.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

import numpy as np
import pytest

try:
    import mlflow
    import xgboost as xgb
    from sklearn.datasets import make_classification, make_regression

    from yagye_data.training.evaluation import (
        ClassifierMetrics,
        RegressorMetrics,
        _save_pr_curve,
        _save_roc_curve,
        evaluate_classifier,
        evaluate_regressor,
    )

    TRAINING_DEPS_AVAILABLE = True
except ImportError:
    TRAINING_DEPS_AVAILABLE = False

pytestmark = pytest.mark.skipif(
    not TRAINING_DEPS_AVAILABLE,
    reason="training optional-dependencies not installed",
)

# ── Synthetic data fixtures ────────────────────────────────────────────────────


@pytest.fixture()
def binary_dataset() -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray, xgb.XGBClassifier]:
    X, y = make_classification(
        n_samples=400,
        n_features=5,
        n_informative=3,
        weights=[0.85, 0.15],  # imbalanced: 15% positives
        random_state=42,
    )
    split = 300
    X_train, X_val = X[:split].astype(np.float32), X[split:].astype(np.float32)
    y_train, y_val = y[:split], y[split:]

    model = xgb.XGBClassifier(n_estimators=20, random_state=42, eval_metric="logloss")
    model.fit(X_train, y_train)
    return X_val, y_val, model.predict_proba(X_val)[:, 1], model, X_train


@pytest.fixture()
def regression_dataset() -> tuple[np.ndarray, np.ndarray, xgb.XGBRegressor, np.ndarray]:
    X, y = make_regression(n_samples=300, n_features=4, noise=5.0, random_state=42)
    X_train, X_val = X[:240].astype(np.float32), X[240:].astype(np.float32)
    y_train, y_val = y[:240].astype(np.float32), y[240:].astype(np.float32)

    model = xgb.XGBRegressor(n_estimators=20, random_state=42)
    model.fit(X_train, y_train)
    return X_val, y_val, model, X_train


# ── ClassifierMetrics ─────────────────────────────────────────────────────────


def test_evaluate_classifier_returns_metrics(
    binary_dataset: tuple,
) -> None:
    X_val, y_val, y_score, model, X_train = binary_dataset
    feature_names = [f"f{i}" for i in range(X_val.shape[1])]

    metrics = evaluate_classifier(
        y_true=y_val,
        y_score=y_score,
        feature_names=feature_names,
        model=model,
        X_val=X_val,
        model_name="test_model",
    )

    assert isinstance(metrics, ClassifierMetrics)
    assert 0.0 <= metrics.auc_pr <= 1.0
    assert 0.0 <= metrics.auc_roc <= 1.0
    assert metrics.auc_roc > 0.5, "XGBoost should beat random on this dataset"
    assert 0.0 <= metrics.precision_at_threshold <= 1.0
    assert 0.0 <= metrics.recall_at_threshold <= 1.0
    assert 0.0 <= metrics.f1_at_threshold <= 1.0
    assert 0.0 < metrics.positive_rate < 1.0


def test_auc_pr_not_same_as_auc_roc(binary_dataset: tuple) -> None:
    """For imbalanced data AUCPR < AUC-ROC — they are different metrics."""
    X_val, y_val, y_score, model, _ = binary_dataset
    feature_names = [f"f{i}" for i in range(X_val.shape[1])]

    metrics = evaluate_classifier(
        y_true=y_val,
        y_score=y_score,
        feature_names=feature_names,
        model=model,
        X_val=X_val,
    )

    # On imbalanced data these should differ
    assert metrics.auc_pr != metrics.auc_roc


def test_evaluate_classifier_without_mlflow_run(binary_dataset: tuple) -> None:
    """evaluate_classifier must not raise when no MLflow run is active."""
    X_val, y_val, y_score, model, _ = binary_dataset
    feature_names = [f"f{i}" for i in range(X_val.shape[1])]

    # Outside any mlflow.start_run() context — should complete silently
    metrics = evaluate_classifier(
        y_true=y_val,
        y_score=y_score,
        feature_names=feature_names,
        model=model,
        X_val=X_val,
    )
    assert isinstance(metrics, ClassifierMetrics)


def test_evaluate_classifier_logs_to_mlflow(
    binary_dataset: tuple, tmp_path: pytest.TempdirFactory
) -> None:
    X_val, y_val, y_score, model, _ = binary_dataset
    feature_names = [f"f{i}" for i in range(X_val.shape[1])]

    mlflow.set_tracking_uri(f"sqlite:///{tmp_path}/mlflow.db")
    mlflow.set_experiment("test_experiment")

    with mlflow.start_run() as run:
        metrics = evaluate_classifier(
            y_true=y_val,
            y_score=y_score,
            feature_names=feature_names,
            model=model,
            X_val=X_val,
            model_name="test_model",
        )

    client = mlflow.tracking.MlflowClient(tracking_uri=f"sqlite:///{tmp_path}/mlflow.db")
    logged = client.get_run(run.info.run_id).data.metrics

    assert "auc_pr" in logged
    assert "auc_roc" in logged
    assert abs(logged["auc_pr"] - metrics.auc_pr) < 1e-4
    assert abs(logged["auc_roc"] - metrics.auc_roc) < 1e-4


def test_evaluate_classifier_logs_artifacts_to_mlflow(
    binary_dataset: tuple, tmp_path: pytest.TempdirFactory
) -> None:
    X_val, y_val, y_score, model, _ = binary_dataset
    feature_names = [f"f{i}" for i in range(X_val.shape[1])]

    mlflow.set_tracking_uri(f"sqlite:///{tmp_path}/mlflow2.db")
    mlflow.set_experiment("test_experiment")

    with mlflow.start_run() as run:
        evaluate_classifier(
            y_true=y_val,
            y_score=y_score,
            feature_names=feature_names,
            model=model,
            X_val=X_val,
            model_name="routing_predictor",
        )

    client = mlflow.tracking.MlflowClient()
    client = mlflow.tracking.MlflowClient(tracking_uri=f"sqlite:///{tmp_path}/mlflow2.db")
    artifacts = [
        a.path
        for a in client.list_artifacts(run.info.run_id, "evaluation/routing_predictor")
    ]
    # At minimum, ROC and PR curves must be logged
    artifact_names = {a.split("/")[-1] for a in artifacts}
    assert "roc_curve.png" in artifact_names
    assert "pr_curve.png" in artifact_names
    assert "confusion_matrix.png" in artifact_names
    assert "feature_importance.png" in artifact_names


# ── RegressorMetrics ──────────────────────────────────────────────────────────


def test_evaluate_regressor_returns_metrics(regression_dataset: tuple) -> None:
    X_val, y_val, model, _ = regression_dataset
    y_pred = model.predict(X_val)
    feature_names = [f"f{i}" for i in range(X_val.shape[1])]

    metrics = evaluate_regressor(
        y_true=y_val,
        y_pred=y_pred,
        feature_names=feature_names,
        model=model,
        X_val=X_val,
        model_name="reserve_recommender",
    )

    assert isinstance(metrics, RegressorMetrics)
    assert metrics.mae >= 0
    assert metrics.rmse >= metrics.mae  # RMSE >= MAE always


def test_evaluate_regressor_without_mlflow_run(regression_dataset: tuple) -> None:
    X_val, y_val, model, _ = regression_dataset
    y_pred = model.predict(X_val)
    feature_names = [f"f{i}" for i in range(X_val.shape[1])]

    metrics = evaluate_regressor(
        y_true=y_val,
        y_pred=y_pred,
        feature_names=feature_names,
        model=model,
        X_val=X_val,
    )
    assert isinstance(metrics, RegressorMetrics)


# ── Plot generators (smoke tests — just check they don't raise) ───────────────


def test_save_roc_curve_writes_file(
    binary_dataset: tuple, tmp_path: pytest.TempdirFactory
) -> None:
    from pathlib import Path

    X_val, y_val, y_score, _, _ = binary_dataset
    out = Path(tmp_path) / "roc.png"
    _save_roc_curve(y_val, y_score, out)
    assert out.exists()
    assert out.stat().st_size > 1000  # non-empty PNG


def test_save_pr_curve_writes_file(
    binary_dataset: tuple, tmp_path: pytest.TempdirFactory
) -> None:
    from pathlib import Path

    X_val, y_val, y_score, _, _ = binary_dataset
    out = Path(tmp_path) / "pr.png"
    _save_pr_curve(y_val, y_score, out)
    assert out.exists()
    assert out.stat().st_size > 1000
