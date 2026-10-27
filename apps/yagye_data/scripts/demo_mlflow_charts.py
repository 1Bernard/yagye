#!/usr/bin/env python
"""Demo: log evaluation charts to MLflow using synthetic data.

Run this to populate the MLflow UI with a realistic set of training artifacts
before real payment data is available.  It trains a small XGBoost routing
predictor on synthetic data, then calls evaluate_classifier() which logs:

  - Scalar metrics: AUCPR, AUC-ROC, precision, recall, F1
  - roc_curve.png       — true vs false positive rate
  - pr_curve.png        — precision vs recall (primary metric)
  - calibration.png     — "does score 0.8 mean 80% success?"
  - confusion_matrix.png
  - feature_importance.png — bar chart of XGBoost gain
  - shap_beeswarm.png   — RED = high feature value pushes score UP
                          BLUE = low feature value pushes score DOWN

Usage:
    # Against the docker-compose MLflow server:
    MLFLOW_TRACKING_URI=http://localhost:5001 uv run python scripts/demo_mlflow_charts.py

    # Local file store (no server needed):
    uv run python scripts/demo_mlflow_charts.py
"""

import os

import mlflow
import numpy as np
import xgboost as xgb
from sklearn.datasets import make_classification
from sklearn.model_selection import train_test_split

from yagye_data.shared.logging import configure_logging, get_logger
from yagye_data.training.evaluation import evaluate_classifier, evaluate_regressor

configure_logging(use_json=False)
logger = get_logger(__name__)

TRACKING_URI = os.getenv("MLFLOW_TRACKING_URI", "http://localhost:5001")
mlflow.set_tracking_uri(TRACKING_URI)

_FEATURE_NAMES = [
    "provider_kind_enc",
    "success_rate",
    "p50_latency_ms",
    "p95_latency_ms",
    "rolling_24h_success_rate",
    "attempt_count",
    "hour_of_day",
    "day_of_week",
    "amount_bucket",
]

_REGRESSOR_FEATURES = [
    "success_rate",
    "failure_count",
    "total_attempts",
    "gross_volume_minor",
    "rolling_7d_failure_rate",
    "days_since_first_txn",
    "method_count",
]


def demo_routing_predictor() -> None:
    """Routing predictor — binary classifier (payment success / failure)."""
    mlflow.set_experiment("routing_predictor")

    # Imbalanced: ~80% success (realistic for a payment network)
    X, y = make_classification(
        n_samples=2000,
        n_features=len(_FEATURE_NAMES),
        n_informative=6,
        n_redundant=2,
        weights=[0.2, 0.8],   # 20% failure, 80% success → imbalanced
        flip_y=0.05,
        random_state=42,
    )
    X = X.astype(np.float32)
    X_train, X_val, y_train, y_val = train_test_split(X, y, test_size=0.25, random_state=42)

    hyperparams = {
        "n_estimators": 200,
        "max_depth": 6,
        "learning_rate": 0.05,
        "subsample": 0.8,
        "colsample_bytree": 0.8,
    }

    with mlflow.start_run(run_name="synthetic_demo"):
        mlflow.log_params(hyperparams)
        mlflow.set_tag("data_source", "synthetic")
        mlflow.set_tag("note", "Demo run — replace with real Silver Parquet data post-P22")

        model = xgb.XGBClassifier(**hyperparams, eval_metric="logloss", random_state=42)
        model.fit(X_train, y_train, eval_set=[(X_val, y_val)], verbose=False)

        y_score = model.predict_proba(X_val)[:, 1]
        metrics = evaluate_classifier(
            y_true=y_val,
            y_score=y_score,
            feature_names=_FEATURE_NAMES,
            model=model,
            X_val=X_val,
            operating_threshold=0.60,
            model_name="routing_predictor",
        )

        logger.info(
            "demo.routing_predictor.done",
            auc_pr=round(metrics.auc_pr, 4),
            auc_roc=round(metrics.auc_roc, 4),
            f1=round(metrics.f1_at_threshold, 4),
        )


def demo_risk_scorer() -> None:
    """Risk scorer — binary classifier (fraud / clean)."""
    mlflow.set_experiment("risk_scorer")

    # Very imbalanced: ~5% fraud rate
    X, y = make_classification(
        n_samples=3000,
        n_features=10,
        n_informative=5,
        n_redundant=3,
        weights=[0.95, 0.05],
        flip_y=0.01,
        random_state=7,
    )
    X = X.astype(np.float32)
    X_train, X_val, y_train, y_val = train_test_split(X, y, test_size=0.25, random_state=7)

    feature_names = [
        "success_rate", "failure_count", "total_attempts", "gross_volume_minor",
        "rolling_7d_failure_rate", "days_since_first_txn",
        "customer_merchant_count", "customer_attempt_count",
        "customer_failure_rate", "customer_rolling_24h_failure_rate",
    ]

    with mlflow.start_run(run_name="synthetic_demo"):
        mlflow.log_params({"n_estimators": 300, "max_depth": 5, "class_weight": "balanced"})
        mlflow.set_tag("data_source", "synthetic")

        model = xgb.XGBClassifier(
            n_estimators=300, max_depth=5,
            scale_pos_weight=19,  # 95/5 ratio
            eval_metric="logloss", random_state=7,
        )
        model.fit(X_train, y_train, verbose=False)

        y_score = model.predict_proba(X_val)[:, 1]
        metrics = evaluate_classifier(
            y_true=y_val,
            y_score=y_score,
            feature_names=feature_names,
            model=model,
            X_val=X_val,
            operating_threshold=0.70,
            model_name="risk_scorer",
        )

        logger.info(
            "demo.risk_scorer.done",
            auc_pr=round(metrics.auc_pr, 4),
            positive_rate=round(metrics.positive_rate, 4),
        )


def demo_reserve_recommender() -> None:
    """Reserve recommender — regressor (target reserve %)."""
    from sklearn.datasets import make_regression
    from yagye_data.training.evaluation import evaluate_regressor

    mlflow.set_experiment("reserve_recommender")

    X, y = make_regression(n_samples=1500, n_features=len(_REGRESSOR_FEATURES), noise=1.5, random_state=3)
    X = X.astype(np.float32)
    y = (y - y.min()) / (y.max() - y.min()) * 20  # scale to 0–20% reserve range
    y = y.astype(np.float32)
    X_train, X_val, y_train, y_val = train_test_split(X, y, test_size=0.25, random_state=3)

    with mlflow.start_run(run_name="synthetic_demo"):
        mlflow.log_params({"n_estimators": 200, "max_depth": 5})
        mlflow.set_tag("data_source", "synthetic")

        model = xgb.XGBRegressor(n_estimators=200, max_depth=5, random_state=3)
        model.fit(X_train, y_train, verbose=False)

        y_pred = model.predict(X_val)
        metrics = evaluate_regressor(
            y_true=y_val,
            y_pred=y_pred,
            feature_names=_REGRESSOR_FEATURES,
            model=model,
            X_val=X_val,
            model_name="reserve_recommender",
        )

        logger.info(
            "demo.reserve_recommender.done",
            mae=round(metrics.mae, 4),
            rmse=round(metrics.rmse, 4),
        )


if __name__ == "__main__":
    logger.info("demo.start", mlflow_uri=TRACKING_URI)
    demo_routing_predictor()
    demo_risk_scorer()
    demo_reserve_recommender()
    logger.info("demo.done", message=f"Open {TRACKING_URI} → pick an experiment → click a run → Artifacts tab")
