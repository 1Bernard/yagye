"""Routing predictor: XGBoost binary classifier.

Predicts P(payment.succeeded | provider, features) so the routing engine can
rank providers by expected success rate given current network conditions.

Label: 1 = payment.succeeded, 0 = payment.failed / payment.indeterminate
Features: provider_health features + current hour-of-day + day-of-week

Training schedule: weekly (cron in Oban, triggers `make train`)
ONNX export: pushed to s3://yagye-ml-models/routing_predictor/model.onnx
"""

import io

import boto3
import xgboost as xgb
from skl2onnx import to_onnx
from skl2onnx.common.data_types import FloatTensorType
from sklearn.model_selection import train_test_split

from yagye_data.config import settings
from yagye_data.shared.duckdb_client import get_connection
from yagye_data.shared.logging import get_logger
from yagye_data.training.features import provider_health
from yagye_data.training.gate import should_promote

logger = get_logger(__name__)

_MODEL_KEY = "routing_predictor/model.onnx"
_FEATURE_COLS = [
    "success_rate",
    "p50_latency_ms",
    "p95_latency_ms",
    "rolling_24h_success_rate",
    "attempt_count",
    "hour_of_day",
    "day_of_week",
]


def train() -> None:
    logger.info("training.routing_predictor.start")

    con = get_connection()
    rel = provider_health.build_features(con)

    df = rel.df()
    df["hour_of_day"] = df["hour_bucket"].dt.hour
    df["day_of_week"] = df["hour_bucket"].dt.dayofweek
    # Label: use success_rate threshold as proxy until we have per-attempt labels
    df["label"] = (df["success_rate"] >= 0.9).astype(int)

    X = df[_FEATURE_COLS].fillna(0).astype("float32")
    y = df["label"]

    X_train, X_val, y_train, y_val = train_test_split(X, y, test_size=0.2, random_state=42)

    model = xgb.XGBClassifier(
        n_estimators=200,
        max_depth=6,
        learning_rate=0.05,
        subsample=0.8,
        colsample_bytree=0.8,
        use_label_encoder=False,
        eval_metric="logloss",
        random_state=42,
    )
    model.fit(X_train, y_train, eval_set=[(X_val, y_val)], verbose=False)

    val_auc = model.get_booster().eval(xgb.DMatrix(X_val, label=y_val), name="val")
    logger.info("training.routing_predictor.eval", metrics=val_auc)

    onnx_model = to_onnx(
        model,
        X_train[:1].values,
        initial_types=[("X", FloatTensorType([None, len(_FEATURE_COLS)]))],
    )

    if should_promote("routing_predictor", onnx_model, X_val, y_val):
        _upload_onnx(onnx_model)
        logger.info("training.routing_predictor.promoted")
    else:
        logger.warning("training.routing_predictor.rejected", reason="champion_holds")


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

    s3 = boto3.client("s3", **kwargs)
    s3.upload_fileobj(buf, settings.ml_models_bucket, _MODEL_KEY)
    logger.info("training.routing_predictor.uploaded", key=_MODEL_KEY)
