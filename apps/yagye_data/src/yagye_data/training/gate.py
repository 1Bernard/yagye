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
    # ONNX classifiers return list of dicts [{0: p0, 1: p1}, ...]
    scores = np.array([p.get(1, 0.0) for p in probs])
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
