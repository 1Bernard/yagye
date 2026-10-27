"""Routing predictor: XGBoost binary classifier.

Predicts P(payment.succeeded | provider, features) so the routing engine can
rank providers by expected success rate given current network conditions.

Label: 1 = payment.succeeded, 0 = payment.failed / payment.indeterminate
        Per-attempt binary from Silver payments — NOT a provider-hour aggregate.

Features: provider_kind_enc, provider_health aggregates from Gold,
          amount_bucket, time-of-day.  Training and serving use the same
          feature definition (see yagye_scoring.models.routing_predictor).

Split: time-based (first 80% of sorted occurrences = train, last 20% = val).
       Random splits cause temporal leakage on time-series data.

Training schedule: weekly (cron in Oban, triggers `make train`)
ONNX export: s3://yagye-ml-models/routing_predictor/{version}/model.onnx
             champion.flag holds the active version string.
"""

import io
import tempfile
from datetime import datetime

import boto3
import mlflow
import xgboost as xgb
from skl2onnx import to_onnx
from skl2onnx.common.data_types import FloatTensorType

from yagye_data.config import settings
from yagye_data.shared.duckdb_client import get_connection
from yagye_data.shared.logging import get_logger
from yagye_data.shared.s3_client import s3_uri
from yagye_data.training.evaluation import evaluate_classifier
from yagye_data.training.gate import should_promote

logger = get_logger(__name__)

_MODEL_NAME = "routing_predictor"
_FEATURE_COLS = [
    "provider_kind_enc",        # 0 = native_rail, 1 = external_psp
    "success_rate",
    "p50_latency_ms",
    "p95_latency_ms",
    "rolling_24h_success_rate",
    "attempt_count",
    "hour_of_day",
    "day_of_week",
    "amount_bucket",            # log10(amount_minor) rounded to nearest 0.5
]
_MIN_TRAINING_ROWS = 100


def train() -> None:
    mlflow.set_experiment(_MODEL_NAME)
    with mlflow.start_run():
        _train_inner()


def _train_inner() -> None:
    logger.info("training.routing_predictor.start")

    hyperparams = {
        "n_estimators": 200,
        "max_depth": 6,
        "learning_rate": 0.05,
        "subsample": 0.8,
        "colsample_bytree": 0.8,
    }
    mlflow.log_params(hyperparams)

    con = get_connection()
    silver_glob = s3_uri(settings.silver_bucket, "payments/**/*.parquet")
    gold_glob = s3_uri(settings.gold_bucket, "provider_health_hourly/**/*.parquet")

    df = con.execute(f"""
        WITH attempts AS (
            SELECT
                event_id,
                occurred_at,
                provider_code,
                COALESCE(provider_kind, 'native_rail')          AS provider_kind,
                amount_minor,
                CASE WHEN event_type = 'payment.succeeded' THEN 1 ELSE 0 END AS label,
                DATE_TRUNC('hour', occurred_at)                 AS hour_bucket,
                EXTRACT(hour FROM occurred_at)::INT             AS hour_of_day,
                EXTRACT(dow  FROM occurred_at)::INT             AS day_of_week
            FROM read_parquet('{silver_glob}', hive_partitioning = true)
            WHERE provider_code IS NOT NULL
              AND (mode IS NULL OR mode = 'live')
        ),
        health AS (
            SELECT
                provider_code,
                hour_bucket,
                success_rate,
                p50_latency_ms,
                p95_latency_ms,
                attempt_count,
                AVG(success_rate) OVER (
                    PARTITION BY provider_code
                    ORDER BY hour_bucket
                    ROWS BETWEEN 23 PRECEDING AND CURRENT ROW
                ) AS rolling_24h_success_rate
            FROM read_parquet('{gold_glob}', hive_partitioning = true)
        )
        SELECT
            a.occurred_at,
            a.label,
            a.hour_of_day,
            a.day_of_week,
            CASE a.provider_kind WHEN 'external_psp' THEN 1 ELSE 0 END     AS provider_kind_enc,
            ROUND(LOG10(NULLIF(a.amount_minor, 0) + 1) * 2.0) / 2.0        AS amount_bucket,
            COALESCE(h.success_rate,             0.5)  AS success_rate,
            COALESCE(h.p50_latency_ms,           0.0)  AS p50_latency_ms,
            COALESCE(h.p95_latency_ms,           0.0)  AS p95_latency_ms,
            COALESCE(h.attempt_count,            0)    AS attempt_count,
            COALESCE(h.rolling_24h_success_rate, 0.5)  AS rolling_24h_success_rate
        FROM attempts a
        LEFT JOIN health h
            ON  a.provider_code = h.provider_code
            AND a.hour_bucket   = h.hour_bucket
        ORDER BY a.occurred_at
    """).df()

    if len(df) < _MIN_TRAINING_ROWS:
        logger.warning(
            "training.routing_predictor.skipped",
            reason="insufficient_data",
            rows=len(df),
        )
        return

    # Time-based split — preserves temporal order to avoid look-ahead leakage
    cutoff_pos = int(len(df) * 0.8)
    cutoff = df["occurred_at"].iloc[cutoff_pos]
    train_mask = df["occurred_at"] <  cutoff
    val_mask   = df["occurred_at"] >= cutoff

    X = df[_FEATURE_COLS].fillna(0.0).astype("float32")
    y = df["label"]

    X_train = X[train_mask].reset_index(drop=True)
    y_train = y[train_mask].reset_index(drop=True)
    X_val   = X[val_mask].reset_index(drop=True)
    y_val   = y[val_mask].reset_index(drop=True)

    model = xgb.XGBClassifier(
        **hyperparams,
        eval_metric="logloss",
        random_state=42,
    )
    model.fit(X_train, y_train, eval_set=[(X_val, y_val)], verbose=False)

    y_score = model.predict_proba(X_val.values)[:, 1]
    metrics = evaluate_classifier(
        y_true=y_val.values,
        y_score=y_score,
        feature_names=_FEATURE_COLS,
        model=model,
        X_val=X_val.values,
        model_name=_MODEL_NAME,
    )
    logger.info(
        "training.routing_predictor.eval",
        auc_pr=round(metrics.auc_pr, 4),
        auc_roc=round(metrics.auc_roc, 4),
    )

    onnx_model = to_onnx(
        model,
        X_train[:1].values,
        initial_types=[("X", FloatTensorType([None, len(_FEATURE_COLS)]))],
    )

    if should_promote(_MODEL_NAME, onnx_model, X_val.values, y_val.values):
        version = _upload_onnx(_MODEL_NAME, onnx_model)
        mlflow.set_tag("promoted", "true")
        mlflow.set_tag("s3_version", version)
        logger.info("training.routing_predictor.promoted", version=version)
    else:
        mlflow.set_tag("promoted", "false")
        logger.warning("training.routing_predictor.rejected", reason="champion_holds")


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

    # Also log the ONNX model file as an MLflow artifact
    with tempfile.NamedTemporaryFile(suffix=".onnx", delete=False) as f:
        f.write(model_bytes)
        f.flush()
        mlflow.log_artifact(f.name, artifact_path="model")

    logger.info("training.routing_predictor.uploaded", key=model_key, version=version)
    return version
