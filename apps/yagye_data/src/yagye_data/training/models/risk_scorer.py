"""Risk scorer: LightGBM binary classifier.

Predicts P(payment is fraudulent | merchant_features, customer_features)
at payment initiation time.

Label: 1 = flagged (chargeback or compliance.str_filed within 30 days)
       0 = clean

Note: Requires 6 months of labelled chargebacks to train meaningfully.
      Until then this module returns a baseline model (all zeros).

Training schedule: bi-weekly
ONNX export: s3://yagye-ml-models/risk_scorer/model.onnx
"""

import io

import boto3
import lightgbm as lgb
import numpy as np
from sklearn.model_selection import train_test_split

from yagye_data.config import settings
from yagye_data.shared.duckdb_client import get_connection
from yagye_data.shared.logging import get_logger
from yagye_data.training.features import customer_risk, merchant_risk

logger = get_logger(__name__)

_MODEL_KEY = "risk_scorer/model.onnx"
_MERCHANT_FEATURE_COLS = [
    "success_rate",
    "failure_count",
    "total_attempts",
    "gross_volume_minor",
    "rolling_7d_failure_rate",
    "days_since_first_txn",
]
_CUSTOMER_FEATURE_COLS = [
    "merchant_count",
    "attempt_count",
    "failure_rate",
    "rolling_24h_failure_rate",
]


def train() -> None:
    logger.info("training.risk_scorer.start")

    con = get_connection()
    merchant_df = merchant_risk.build_features(con).df()
    customer_df = customer_risk.build_features(con).df()

    if merchant_df.empty or customer_df.empty:
        logger.warning("training.risk_scorer.skipped", reason="insufficient_data")
        return

    # Placeholder label: failure_rate > 0.3 as a training proxy
    merchant_df["label"] = (merchant_df["rolling_7d_failure_rate"] > 0.3).astype(int)

    X_m = merchant_df[_MERCHANT_FEATURE_COLS].fillna(0).astype("float32")
    y = merchant_df["label"]

    X_train, X_val, y_train, y_val = train_test_split(X_m, y, test_size=0.2, random_state=42)

    model = lgb.LGBMClassifier(
        n_estimators=300,
        max_depth=5,
        learning_rate=0.03,
        num_leaves=31,
        subsample=0.8,
        colsample_bytree=0.8,
        class_weight="balanced",
        random_state=42,
    )
    model.fit(X_train, y_train, eval_set=[(X_val, y_val)])

    logger.info(
        "training.risk_scorer.eval",
        val_score=float(np.mean(model.predict(X_val) == y_val)),
    )

    # LightGBM → ONNX via onnxmltools
    try:
        import onnxmltools
        from onnxmltools.convert.common.data_types import FloatTensorType as OnnxFloat
        onnx_model = onnxmltools.convert_lightgbm(
            model,
            initial_types=[("X", OnnxFloat([None, len(_MERCHANT_FEATURE_COLS)]))],
        )
        _upload_onnx(onnx_model)
        logger.info("training.risk_scorer.promoted")
    except Exception:
        logger.exception("training.risk_scorer.onnx_export_failed")


def _upload_onnx(onnx_model: object) -> None:
    buf = io.BytesIO()
    buf.write(onnx_model.SerializeToString())  # type: ignore[attr-defined]
    buf.seek(0)

    kwargs: dict = {
        "region_name": settings.s3_region,
        "aws_access_key_id": settings.s3_access_key_id,
        "aws_secret_access_key": settings.s3_secret_access_key,
    }
    if settings.s3_endpoint_url:
        kwargs["endpoint_url"] = settings.s3_endpoint_url

    boto3.client("s3", **kwargs).upload_fileobj(buf, settings.ml_models_bucket, _MODEL_KEY)
