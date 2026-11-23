"""Champion-challenger gate: only promote a new model if it beats the current champion.

The gate fetches the live ONNX model from S3, scores the validation set with
both champion and challenger, and returns True only if the challenger wins by
at least `min_improvement` in AUCPR (Area Under Precision-Recall Curve).

AUCPR is the primary metric — it is more informative than AUC-ROC for imbalanced
classes where failure/fraud events are rare (a model that always predicts "success"
gets a high AUC-ROC but a low AUCPR matching the base positive rate).

This prevents a bad weekly retrain from silently degrading the routing predictor.
"""

import numpy as np
import onnxruntime as ort
from sklearn.metrics import average_precision_score

from yagye_data.config import settings
from yagye_data.shared.logging import get_logger
from yagye_data.shared.s3_client import get_s3_client

logger = get_logger(__name__)

_MIN_IMPROVEMENT = 0.005  # challenger must beat champion by at least 0.5% AUCPR


def gate_on_metrics(metrics: dict, **min_thresholds: float) -> None:
    """Raise ValueError if any metric in `metrics` is below its threshold.

    Usage::

        gate_on_metrics(metrics, min_roc_auc=0.70)
        gate_on_metrics(metrics, min_macro_f1=0.75)
    """
    for kwarg_key, min_val in min_thresholds.items():
        # Strip the leading "min_" to get the metric name, e.g. min_roc_auc → roc_auc
        metric_name = kwarg_key[4:] if kwarg_key.startswith("min_") else kwarg_key
        actual = metrics.get(metric_name, 0.0)
        if actual < min_val:
            raise ValueError(
                f"Training gate failed: {metric_name}={actual:.4f} < required {min_val}"
            )
        logger.info("gate.passed", metric=metric_name, actual=round(actual, 4), threshold=min_val)


def should_promote(
    model_name: str,
    challenger_onnx: object,
    X_val: "np.ndarray",  # type: ignore[type-arg]
    y_val: "np.ndarray",  # type: ignore[type-arg]
    min_improvement: float = _MIN_IMPROVEMENT,
) -> bool:
    """Return True if challenger beats champion on the validation set (AUCPR)."""
    challenger_score = _score_onnx_bytes(
        challenger_onnx.SerializeToString(),  # type: ignore[union-attr]
        X_val,
        y_val,
    )

    champion_bytes = _fetch_champion(model_name)
    if champion_bytes is None:
        logger.info("gate.no_champion", model=model_name, action="promote")
        return True

    champion_score = _score_onnx_bytes(champion_bytes, X_val, y_val)
    delta = challenger_score - champion_score

    logger.info(
        "gate.comparison",
        model=model_name,
        champion_aucpr=round(champion_score, 4),
        challenger_aucpr=round(challenger_score, 4),
        delta=round(delta, 4),
        min_improvement=min_improvement,
    )

    return delta >= min_improvement


def _score_onnx_bytes(
    model_bytes: bytes,
    X_val: "np.ndarray",  # type: ignore[type-arg]
    y_val: "np.ndarray",  # type: ignore[type-arg]
) -> float:
    sess = ort.InferenceSession(model_bytes)
    input_name = sess.get_inputs()[0].name
    probs = sess.run(None, {input_name: X_val.astype(np.float32)})[1]
    # zipmap=False returns a 2D ndarray [n_samples, n_classes]; column 1 = P(class=1)
    scores = probs[:, 1] if hasattr(probs, "ndim") else np.array([p.get(1, 0.0) for p in probs])
    return float(average_precision_score(y_val, scores))


def _fetch_champion(model_name: str) -> bytes | None:
    s3 = get_s3_client()

    # Try versioned layout: read champion.flag → version → fetch that version's model
    try:
        flag_obj = s3.get_object(
            Bucket=settings.ml_models_bucket, Key=f"{model_name}/champion.flag"
        )
        version = flag_obj["Body"].read().decode().strip()
        if version:
            obj = s3.get_object(
                Bucket=settings.ml_models_bucket,
                Key=f"{model_name}/{version}/model.onnx",
            )
            return obj["Body"].read()
    except Exception:
        pass

    # Fallback: flat layout (pre-versioning compat)
    try:
        obj = s3.get_object(
            Bucket=settings.ml_models_bucket, Key=f"{model_name}/model.onnx"
        )
        return obj["Body"].read()
    except Exception:
        return None
