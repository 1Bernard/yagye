"""Churn predictor: XGBoost binary classifier.

Predicts P(merchant churns within 90 days) based on transaction decline,
support contact rate, and product usage signals.

Label: 1 = no transactions in the subsequent 90 days
       0 = active

Training schedule: monthly
ONNX export: s3://yagye-ml-models/churn_predictor/model.onnx
"""

import io

import boto3
import xgboost as xgb
from sklearn.model_selection import train_test_split

from yagye_data.config import settings
from yagye_data.shared.duckdb_client import get_connection
from yagye_data.shared.logging import get_logger
from yagye_data.training.features import merchant_risk

logger = get_logger(__name__)

_MODEL_KEY = "churn_predictor/model.onnx"
_FEATURE_COLS = [
    "success_rate",
    "failure_count",
    "total_attempts",
    "gross_volume_minor",
    "rolling_7d_failure_rate",
    "days_since_first_txn",
    "method_count",
    "currency_count",
]


def train() -> None:
    logger.info("training.churn_predictor.start")

    con = get_connection()
    df = merchant_risk.build_features(con, training_window_days=365).df()

    if df.empty:
        logger.warning("training.churn_predictor.skipped", reason="insufficient_data")
        return

    # Proxy label: merchants with total_attempts < 5 in last 30 days are "at risk"
    df["label"] = (df["total_attempts"] < 5).astype(int)

    X = df[_FEATURE_COLS].fillna(0).astype("float32")
    y = df["label"]

    X_train, X_val, y_train, y_val = train_test_split(X, y, test_size=0.2, random_state=42)

    model = xgb.XGBClassifier(
        n_estimators=150,
        max_depth=4,
        learning_rate=0.05,
        subsample=0.8,
        colsample_bytree=0.8,
        scale_pos_weight=(y_train == 0).sum() / max((y_train == 1).sum(), 1),
        use_label_encoder=False,
        eval_metric="auc",
        random_state=42,
    )
    model.fit(X_train, y_train, eval_set=[(X_val, y_val)], verbose=False)

    from skl2onnx import to_onnx
    from skl2onnx.common.data_types import FloatTensorType

    onnx_model = to_onnx(
        model,
        X_train[:1].values,
        initial_types=[("X", FloatTensorType([None, len(_FEATURE_COLS)]))],
    )

    _upload_onnx(onnx_model)
    logger.info("training.churn_predictor.promoted")


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
