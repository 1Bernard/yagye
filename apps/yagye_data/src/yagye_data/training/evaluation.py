"""ML model evaluation: metrics, charts, and MLflow logging.

Call evaluate_classifier() or evaluate_regressor() inside an active MLflow
run and everything — scalar metrics, ROC curve, PR curve, calibration plot,
confusion matrix, feature importance bar chart, and SHAP beeswarm — is logged
as MLflow artifacts automatically.

These functions return the metrics dataclass even when no MLflow run is active
(e.g. in tests), so training is never blocked by MLflow unavailability.

The SHAP beeswarm plot answers "why did the model predict this?":
  - Each row is one feature
  - Each dot is one validation example
  - Horizontal position = impact on model output (right = pushes score up)
  - Color = feature value (red = high, blue = low)
"""

from __future__ import annotations

import contextlib
import tempfile
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

import matplotlib

matplotlib.use("Agg")  # non-interactive: must be before pyplot import
import matplotlib.pyplot as plt
import numpy as np
from sklearn.calibration import calibration_curve
from sklearn.metrics import (
    ConfusionMatrixDisplay,
    average_precision_score,
    confusion_matrix,
    mean_absolute_error,
    mean_squared_error,
    precision_recall_curve,
    roc_auc_score,
    roc_curve,
)

from yagye_data.shared.logging import get_logger

logger = get_logger(__name__)


@dataclass
class ClassifierMetrics:
    auc_roc: float
    auc_pr: float  # primary metric — more reliable for imbalanced classes
    precision_at_threshold: float
    recall_at_threshold: float
    f1_at_threshold: float
    positive_rate: float  # fraction of positives in y_true


@dataclass
class RegressorMetrics:
    mae: float
    rmse: float


# ── Public API ────────────────────────────────────────────────────────────────


def evaluate_classifier(
    y_true: np.ndarray,
    y_score: np.ndarray,
    feature_names: list[str],
    model: Any,
    X_val: np.ndarray,
    operating_threshold: float = 0.5,
    model_name: str = "model",
) -> ClassifierMetrics:
    """Compute classifier evaluation metrics and log everything to MLflow.

    Works correctly with no active MLflow run — metrics are returned regardless.
    The SHAP beeswarm plot is the "red = high, blue = low" chart.
    """
    auc_roc = float(roc_auc_score(y_true, y_score))
    auc_pr = float(average_precision_score(y_true, y_score))

    y_pred = (y_score >= operating_threshold).astype(int)
    tp = int(((y_pred == 1) & (y_true == 1)).sum())
    fp = int(((y_pred == 1) & (y_true == 0)).sum())
    fn = int(((y_pred == 0) & (y_true == 1)).sum())
    precision = tp / (tp + fp) if (tp + fp) > 0 else 0.0
    recall = tp / (tp + fn) if (tp + fn) > 0 else 0.0
    f1 = 2 * precision * recall / (precision + recall) if (precision + recall) > 0 else 0.0

    metrics = ClassifierMetrics(
        auc_roc=auc_roc,
        auc_pr=auc_pr,
        precision_at_threshold=precision,
        recall_at_threshold=recall,
        f1_at_threshold=f1,
        positive_rate=float(y_true.mean()),
    )

    logger.info(
        "evaluation.classifier",
        model=model_name,
        **{k: round(v, 4) for k, v in asdict(metrics).items()},
    )

    _try_log_classifier_to_mlflow(metrics, y_true, y_score, y_pred, feature_names, model, X_val, model_name)
    return metrics


def evaluate_regressor(
    y_true: np.ndarray,
    y_pred: np.ndarray,
    feature_names: list[str],
    model: Any,
    X_val: np.ndarray,
    model_name: str = "model",
) -> RegressorMetrics:
    mae = float(mean_absolute_error(y_true, y_pred))
    rmse = float(mean_squared_error(y_true, y_pred) ** 0.5)

    metrics = RegressorMetrics(mae=mae, rmse=rmse)

    logger.info("evaluation.regressor", model=model_name, mae=round(mae, 4), rmse=round(rmse, 4))

    _try_log_regressor_to_mlflow(metrics, y_true, y_pred, feature_names, model, X_val, model_name)
    return metrics


# ── MLflow integration ────────────────────────────────────────────────────────


def _try_log_classifier_to_mlflow(
    metrics: ClassifierMetrics,
    y_true: np.ndarray,
    y_score: np.ndarray,
    y_pred: np.ndarray,
    feature_names: list[str],
    model: Any,
    X_val: np.ndarray,
    model_name: str,
) -> None:
    with contextlib.suppress(Exception):
        import mlflow

        if not mlflow.active_run():
            return

        mlflow.log_metrics({k: round(v, 6) for k, v in asdict(metrics).items()})

        with tempfile.TemporaryDirectory() as tmpdir:
            out = Path(tmpdir)
            _save_roc_curve(y_true, y_score, out / "roc_curve.png")
            _save_pr_curve(y_true, y_score, out / "pr_curve.png")
            _save_calibration(y_true, y_score, out / "calibration.png")
            _save_confusion_matrix(y_true, y_pred, out / "confusion_matrix.png")
            if hasattr(model, "feature_importances_"):
                _save_feature_importance(model.feature_importances_, feature_names, out / "feature_importance.png")
            _try_save_shap(model, X_val, feature_names, out / "shap_beeswarm.png")
            mlflow.log_artifacts(tmpdir, artifact_path=f"evaluation/{model_name}")


def _try_log_regressor_to_mlflow(
    metrics: RegressorMetrics,
    y_true: np.ndarray,
    y_pred: np.ndarray,
    feature_names: list[str],
    model: Any,
    X_val: np.ndarray,
    model_name: str,
) -> None:
    with contextlib.suppress(Exception):
        import mlflow

        if not mlflow.active_run():
            return

        mlflow.log_metrics({"mae": round(metrics.mae, 6), "rmse": round(metrics.rmse, 6)})

        with tempfile.TemporaryDirectory() as tmpdir:
            out = Path(tmpdir)
            _save_residual_plot(y_true, y_pred, out / "residuals.png")
            if hasattr(model, "feature_importances_"):
                _save_feature_importance(model.feature_importances_, feature_names, out / "feature_importance.png")
            _try_save_shap(model, X_val, feature_names, out / "shap_beeswarm.png")
            mlflow.log_artifacts(tmpdir, artifact_path=f"evaluation/{model_name}")


# ── Plot generators ───────────────────────────────────────────────────────────


def _save_roc_curve(y_true: np.ndarray, y_score: np.ndarray, path: Path) -> None:
    fpr, tpr, _ = roc_curve(y_true, y_score)
    auc = roc_auc_score(y_true, y_score)

    fig, ax = plt.subplots(figsize=(6, 5))
    ax.plot(fpr, tpr, color="#2563eb", lw=2, label=f"AUC-ROC = {auc:.3f}")
    ax.plot([0, 1], [0, 1], color="#6b7280", lw=1, linestyle="--", label="Random")
    ax.set_xlabel("False Positive Rate")
    ax.set_ylabel("True Positive Rate")
    ax.set_title("ROC Curve")
    ax.legend()
    ax.grid(alpha=0.3)
    fig.tight_layout()
    fig.savefig(path, dpi=120)
    plt.close(fig)


def _save_pr_curve(y_true: np.ndarray, y_score: np.ndarray, path: Path) -> None:
    precision, recall, _ = precision_recall_curve(y_true, y_score)
    auc_pr = average_precision_score(y_true, y_score)
    baseline = float(y_true.mean())

    fig, ax = plt.subplots(figsize=(6, 5))
    ax.plot(recall, precision, color="#16a34a", lw=2, label=f"AUCPR = {auc_pr:.3f}")
    ax.axhline(baseline, color="#6b7280", lw=1, linestyle="--", label=f"Baseline (positive rate = {baseline:.2%})")
    ax.set_xlabel("Recall")
    ax.set_ylabel("Precision")
    ax.set_title("Precision-Recall Curve")
    ax.legend()
    ax.grid(alpha=0.3)
    fig.tight_layout()
    fig.savefig(path, dpi=120)
    plt.close(fig)


def _save_calibration(y_true: np.ndarray, y_score: np.ndarray, path: Path) -> None:
    n_bins = min(10, int(y_true.sum()))
    if n_bins < 3:
        return

    fraction_of_positives, mean_predicted = calibration_curve(y_true, y_score, n_bins=n_bins)

    fig, ax = plt.subplots(figsize=(6, 5))
    ax.plot([0, 1], [0, 1], color="#6b7280", lw=1, linestyle="--", label="Perfect calibration")
    ax.plot(mean_predicted, fraction_of_positives, color="#dc2626", lw=2, marker="o", label="Model")
    ax.set_xlabel("Mean predicted probability")
    ax.set_ylabel("Fraction of positives")
    ax.set_title("Calibration Plot (Reliability Diagram)")
    ax.legend()
    ax.grid(alpha=0.3)
    fig.tight_layout()
    fig.savefig(path, dpi=120)
    plt.close(fig)


def _save_confusion_matrix(y_true: np.ndarray, y_pred: np.ndarray, path: Path) -> None:
    cm = confusion_matrix(y_true, y_pred)
    fig, ax = plt.subplots(figsize=(5, 4))
    disp = ConfusionMatrixDisplay(confusion_matrix=cm, display_labels=["Negative", "Positive"])
    disp.plot(ax=ax, colorbar=False, cmap="Blues")
    ax.set_title("Confusion Matrix")
    fig.tight_layout()
    fig.savefig(path, dpi=120)
    plt.close(fig)


def _save_feature_importance(
    importances: np.ndarray, feature_names: list[str], path: Path
) -> None:
    indices = np.argsort(importances)
    fig, ax = plt.subplots(figsize=(7, max(4, len(feature_names) * 0.4)))
    ax.barh(
        [feature_names[i] for i in indices],
        importances[indices],
        color="#2563eb",
    )
    ax.set_xlabel("Feature Importance (gain)")
    ax.set_title("Feature Importance")
    fig.tight_layout()
    fig.savefig(path, dpi=120)
    plt.close(fig)


def _try_save_shap(
    model: Any, X_val: np.ndarray, feature_names: list[str], path: Path
) -> None:
    with contextlib.suppress(Exception):
        import shap

        # Subsample to keep SHAP computation fast (200 examples is enough for summary)
        n = min(200, len(X_val))
        rng = np.random.default_rng(42)
        idx = rng.choice(len(X_val), n, replace=False)
        X_sample = X_val[idx]

        explainer = shap.TreeExplainer(model)
        shap_values = explainer.shap_values(X_sample)

        # Binary classifiers return a list [neg_class_vals, pos_class_vals]
        if isinstance(shap_values, list):
            shap_values = shap_values[1]

        fig, ax = plt.subplots(figsize=(8, max(5, len(feature_names) * 0.45)))
        shap.summary_plot(
            shap_values,
            X_sample,
            feature_names=feature_names,
            show=False,
            plot_type="dot",  # the classic "beeswarm": red=high value, blue=low value
        )
        plt.title("SHAP Feature Impact (red = high feature value, blue = low)")
        plt.tight_layout()
        plt.savefig(path, dpi=120, bbox_inches="tight")
        plt.close("all")


def _save_residual_plot(y_true: np.ndarray, y_pred: np.ndarray, path: Path) -> None:
    residuals = y_true - y_pred
    fig, axes = plt.subplots(1, 2, figsize=(10, 4))

    axes[0].scatter(y_pred, residuals, alpha=0.4, color="#2563eb", s=10)
    axes[0].axhline(0, color="#dc2626", lw=1)
    axes[0].set_xlabel("Predicted")
    axes[0].set_ylabel("Residual")
    axes[0].set_title("Residuals vs Predicted")
    axes[0].grid(alpha=0.3)

    axes[1].hist(residuals, bins=30, color="#2563eb", alpha=0.7, edgecolor="white")
    axes[1].set_xlabel("Residual")
    axes[1].set_title("Residual Distribution")
    axes[1].grid(alpha=0.3)

    fig.tight_layout()
    fig.savefig(path, dpi=120)
    plt.close(fig)
