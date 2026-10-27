"""Reserve recommender: XGBoost regression.

Predicts the optimal rolling reserve percentage for a merchant given their
historical payment volume, failure patterns, and chargeback rate.

Label: actual chargeback_amount / gross_volume (rolling 30-day)
Features: merchant_risk daily features over 90-day window

Training schedule: monthly
ONNX export: s3://yagye-ml-models/reserve_recommender/{version}/model.onnx
"""

import io
import tempfile
from datetime import datetime

import boto3
import mlflow
import xgboost as xgb
from skl2onnx import to_onnx
from skl2onnx.common.data_types import FloatTensorType
from sklearn.model_selection import train_test_split

from yagye_data.config import settings
from yagye_data.shared.duckdb_client import get_connection
from yagye_data.shared.logging import get_logger
from yagye_data.training.evaluation import evaluate_regressor
from yagye_data.training.features import merchant_risk

logger = get_logger(__name__)

_MODEL_NAME = "reserve_recommender"
_FEATURE_COLS = [
    "success_rate",
    "failure_count",
    "total_attempts",
    "gross_volume_minor",
    "rolling_7d_failure_rate",
    "days_since_first_txn",
    "method_count",
]


def train() -> None:
    mlflow.set_experiment(_MODEL_NAME)
    with mlflow.start_run():
        _train_inner()


def _train_inner() -> None:
    logger.info("training.reserve_recommender.start")

    con = get_connection()
    df = merchant_risk.build_features(con, training_window_days=365).df()

    if df.empty:
        logger.warning("training.reserve_recommender.skipped", reason="insufficient_data")
        return

    # Proxy label: rolling_7d_failure_rate as a reserve need signal
    df["reserve_target"] = (df["rolling_7d_failure_rate"] * 100).clip(0, 20)

    X = df[_FEATURE_COLS].fillna(0).astype("float32")
    y = df["reserve_target"].astype("float32")

    X_train, X_val, y_train, y_val = train_test_split(X, y, test_size=0.2, random_state=42)

    hyperparams = {
        "n_estimators": 200,
        "max_depth": 5,
        "learning_rate": 0.05,
        "subsample": 0.8,
        "colsample_bytree": 0.8,
    }
    mlflow.log_params(hyperparams)

    model = xgb.XGBRegressor(**hyperparams, random_state=42)
    model.fit(X_train, y_train, eval_set=[(X_val, y_val)], verbose=False)

    y_pred = model.predict(X_val.values)
    metrics = evaluate_regressor(
        y_true=y_val.values,
        y_pred=y_pred,
        feature_names=_FEATURE_COLS,
        model=model,
        X_val=X_val.values,
        model_name=_MODEL_NAME,
    )
    logger.info(
        "training.reserve_recommender.eval",
        mae=round(metrics.mae, 4),
        rmse=round(metrics.rmse, 4),
    )

    onnx_model = to_onnx(
        model,
        X_train[:1].values,
        initial_types=[("X", FloatTensorType([None, len(_FEATURE_COLS)]))],
    )

    version = _upload_onnx(_MODEL_NAME, onnx_model)
    mlflow.set_tag("s3_version", version)
    logger.info("training.reserve_recommender.promoted", version=version)


def _upload_onnx(model_name: str, onnx_model: object) -> str:
    version = datetime.utcnow().strftime("v%Y%m%d_%H%M%S")
    model_key = f"{model_name}/{version}/model.onnx"
    flag_key = f"{model_name}/champion.flag"

    model_bytes = onnx_model.SerializeToString()  # type: ignore[attr-defined]

    kwargs: dict = {
        "region_name": settings.s3_region,
        "aws_access_key_id": settings.s3_access_key_id,
        "aws_secret_access_key": settings.s3_secret_access_key,
    }
    if settings.s3_endpoint_url:
        kwargs["endpoint_url"] = settings.s3_endpoint_url

    s3 = boto3.client("s3", **kwargs)
    s3.upload_fileobj(io.BytesIO(model_bytes), settings.ml_models_bucket, model_key)
    s3.put_object(Bucket=settings.ml_models_bucket, Key=flag_key, Body=version.encode())

    with tempfile.NamedTemporaryFile(suffix=".onnx", delete=False) as f:
        f.write(model_bytes)
        f.flush()
        mlflow.log_artifact(f.name, artifact_path="model")

    return version
