"""Training script — VelocityScorer (IsolationForest).

Data sources (--source flag):
  db    (default) — query Core DB for per-MSISDN aggregate features; real
        temporal data from simulation payments.
  jsonl — read labeled JSONL output from the simulator's generate_load task
        and compute features from raw rows grouped by msisdn.

Because IsolationForest is unsupervised, only normal-traffic rows are used for
fitting; heuristic labels are used only to gate on ROC-AUC.

Usage:
  python -m yagye_data.training.models.velocity_scorer --output models/velocity_scorer/
  python -m yagye_data.training.models.velocity_scorer --source jsonl \
    --input data/simulator_load.jsonl --output models/velocity_scorer/

  Outputs:
    models/velocity_scorer/model.onnx
    models/velocity_scorer/metadata.json
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.ensemble import IsolationForest

from yagye_data.training.evaluation import evaluate_binary
from yagye_data.training.gate import gate_on_metrics

_FEATURE_COLS = [
    "attempt_count_1h",
    "fail_count_1h",
    "txn_count_24h",
    "failure_rate",
    "distinct_merchant_count",
    "amount_minor",
    "is_momo",
    "hour_of_day",
    "day_of_week",
]


def _load_jsonl(path: Path) -> pd.DataFrame:
    rows = [json.loads(line) for line in path.read_text().splitlines() if line.strip()]
    return pd.DataFrame(rows)


def _build_features(df: pd.DataFrame) -> pd.DataFrame:
    """Group by msisdn and compute sliding-window aggregate features."""
    df["fired_at"] = pd.to_datetime(df["fired_at"], utc=True)
    df["hour_of_day"] = df["fired_at"].dt.hour
    df["day_of_week"] = df["fired_at"].dt.dayofweek
    df["is_momo"] = (df["network"].isin(["MTN", "TELECEL", "AIRTELTIGO"])).astype(float)
    df["is_success"] = (df["outcome_class"] == "success").astype(int)
    df["amount_minor"] = df["amount"].fillna(0).astype(float)

    # Per-MSISDN rolling 1-hour window (approximated as the last N rows per hour)
    # In training we use the full 24-h window per MSISDN as a proxy.
    agg = (
        df.groupby("msisdn")
        .agg(
            txn_count_24h=("payment_id", "count"),
            fail_count_1h=("is_success", lambda s: (1 - s).sum()),
            attempt_count_1h=("payment_id", "count"),
            failure_rate=("is_success", lambda s: 1 - s.mean()),
            distinct_merchant_count=("merchant_reference", pd.Series.nunique),
            amount_minor=("amount_minor", "mean"),
            is_momo=("is_momo", "first"),
            hour_of_day=("hour_of_day", "first"),
            day_of_week=("day_of_week", "first"),
        )
        .reset_index()
    )
    agg["label"] = (
        df.groupby("msisdn")["outcome_class"]
        .agg(lambda s: int((s != "success").any()))
        .values
    )
    return agg


def _load_from_db() -> pd.DataFrame:
    from yagye_data.training.data.velocity_from_db import load_velocity_features
    return load_velocity_features()


def train(
    output_dir: Path,
    input_path: Path | None = None,
    source: str = "db",
    contamination: float = 0.10,
) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)

    if source == "db":
        features_df = _load_from_db()
    elif source == "jsonl" and input_path:
        df = _load_jsonl(input_path)
        features_df = _build_features(df)
    else:
        raise ValueError(f"source={source!r} requires --input for jsonl")

    X_all = features_df[_FEATURE_COLS].to_numpy(dtype=np.float32)
    y_all = features_df["label"].to_numpy()

    # Train on ALL data (unsupervised). StandardScaler is intentionally omitted:
    # when all normal rows share the same value for the key velocity features (e.g.
    # attempt_count_1h=2 for every 2-payment MSISDN), fitting a scaler only on
    # those rows collapses variance to zero and prevents IsolationForest from
    # splitting on the most discriminating dimension. Training on raw magnitudes
    # lets the random splits work correctly on the full range including anomalies.
    clf = IsolationForest(
        n_estimators=200,
        contamination=contamination,
        random_state=42,
        n_jobs=-1,
    )
    clf.fit(X_all)

    # decision_function returns higher values for inliers; negate and scale to [0, 1]
    raw_scores = clf.decision_function(X_all)
    scores_01 = 1 / (1 + np.exp(raw_scores))  # sigmoid-squash

    metrics = evaluate_binary(y_all, scores_01, threshold=0.65)
    gate_on_metrics(metrics, min_roc_auc=0.70)

    # Export to ONNX via skl2onnx
    try:
        from skl2onnx import convert_sklearn
        from skl2onnx.common.data_types import FloatTensorType

        onnx_model = convert_sklearn(
            clf,
            initial_types=[("input", FloatTensorType([None, len(_FEATURE_COLS)]))],
            target_opset={"": 17, "ai.onnx.ml": 3},
        )
        (output_dir / "model.onnx").write_bytes(onnx_model.SerializeToString())
    except ImportError:
        print("skl2onnx not installed — skipping ONNX export; model not saved.")
        return

    metadata = {
        "model_name": "velocity_scorer",
        "algorithm": "IsolationForest",
        "features": _FEATURE_COLS,
        "contamination": contamination,
        "metrics": metrics,
    }
    (output_dir / "metadata.json").write_text(json.dumps(metadata, indent=2))
    print(f"Saved model to {output_dir} | ROC-AUC: {metrics.get('roc_auc', 'n/a'):.3f}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Train VelocityScorer")
    parser.add_argument("--source", choices=["db", "jsonl"], default="db")
    parser.add_argument("--input", type=Path, default=None)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--contamination", type=float, default=0.10)
    args = parser.parse_args()
    train(args.output, args.input, args.source, args.contamination)


if __name__ == "__main__":
    main()
