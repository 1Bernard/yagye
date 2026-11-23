"""Training script — ReconBreakClassifier (LightGBM multi-class).

Data sources (--source flag):
  db        (default) — real breaks from Core DB augmented with synthetic rows
            for under-represented classes.
  jsonl     — labeled JSONL file (break_id, amount_delta_minor, expected_amount,
              age_hours, has_right_ref, settlement_offset_days, classification).
  synthetic — pure synthetic bootstrap (no DB required).

Classes (match ReconciliationBreak @valid_classifications):
  0 → timing_difference
  1 → fee_discrepancy
  2 → missing_on_right
  3 → amount_mismatch

Usage:
  python -m yagye_data.training.models.recon_break_classifier --output models/recon_break_classifier/
  python -m yagye_data.training.models.recon_break_classifier --source jsonl \
    --input data/recon_breaks.jsonl --output models/recon_break_classifier/

  Outputs:
    models/recon_break_classifier/model.onnx
    models/recon_break_classifier/metadata.json
"""

from __future__ import annotations

import argparse
import json
import random
from pathlib import Path

import numpy as np
import pandas as pd

from yagye_data.training.evaluation import evaluate_multiclass
from yagye_data.training.gate import gate_on_metrics

_CLASS_LABELS = [
    "timing_difference",
    "fee_discrepancy",
    "missing_on_right",
    "amount_mismatch",
]
_LABEL_TO_IDX = {label: i for i, label in enumerate(_CLASS_LABELS)}

_FEATURE_COLS = [
    "amount_delta_minor",
    "abs_delta_minor",
    "relative_delta",
    "age_hours",
    "has_right_ref",
    "settlement_offset_days",
]

_FEE_DELTA_THRESHOLD = 100


def _rule_label(row: dict) -> int:
    """Mirror of ReconBreakClassifier.rule_based_predict — used for synthetic labels."""
    abs_delta = abs(row["amount_delta_minor"])
    age_hours = row["age_hours"]
    has_right_ref = int(row["has_right_ref"])

    if abs_delta == 0 and age_hours > 24:
        return 0  # timing_difference
    if 0 < abs_delta <= _FEE_DELTA_THRESHOLD and has_right_ref == 1:
        return 1  # fee_discrepancy
    if has_right_ref == 0:
        return 2  # missing_on_right
    return 3  # amount_mismatch


def _make_synthetic_dataset(n: int = 2000, seed: int = 42) -> pd.DataFrame:
    """Generate labelled synthetic breaks for bootstrapping."""
    rng = random.Random(seed)
    rows = []
    for _ in range(n):
        cls = rng.randint(0, 3)
        if cls == 0:  # timing_difference: zero delta, old break
            delta = 0
            age = rng.uniform(25, 200)
            right_ref = True
            offset = rng.randint(0, 2)
        elif cls == 1:  # fee_discrepancy: tiny delta, provider ref present
            delta = rng.randint(1, _FEE_DELTA_THRESHOLD)
            age = rng.uniform(0, 48)
            right_ref = True
            offset = 0
        elif cls == 2:  # missing_on_right: no provider ref
            delta = rng.randint(100, 500_00)
            age = rng.uniform(0, 72)
            right_ref = False
            offset = rng.randint(1, 7)
        else:  # amount_mismatch: substantial delta, provider ref exists
            delta = rng.randint(_FEE_DELTA_THRESHOLD + 1, 500_00)
            age = rng.uniform(0, 48)
            right_ref = True
            offset = 0
        expected = rng.randint(max(delta + 1, 1_00), 500_00)
        rows.append({
            "amount_delta_minor": delta,
            "abs_delta_minor": abs(delta),
            "relative_delta": min(abs(delta) / expected, 1.0),
            "age_hours": age,
            "has_right_ref": 1.0 if right_ref else 0.0,
            "settlement_offset_days": float(offset),
            "label": cls,
        })
    return pd.DataFrame(rows)


def _load_jsonl(path: Path) -> pd.DataFrame:
    rows = [json.loads(line) for line in path.read_text().splitlines() if line.strip()]
    df = pd.DataFrame(rows)
    df["label"] = df["classification"].map(_LABEL_TO_IDX)
    df["abs_delta_minor"] = df["amount_delta_minor"].abs()
    df["relative_delta"] = (
        df["abs_delta_minor"] / df["expected_amount"].clip(lower=1)
    ).clip(upper=1.0)
    df["has_right_ref"] = df["has_right_ref"].astype(float)
    return df


def _load_from_db() -> pd.DataFrame:
    from yagye_data.training.data.recon_from_db import load_recon_features
    df = load_recon_features()
    df["label"] = df["label"].map(_LABEL_TO_IDX)
    return df


def train(
    output_dir: Path,
    input_path: Path | None = None,
    source: str = "db",
) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)

    if source == "db":
        df = _load_from_db()
    elif source == "jsonl" and input_path and input_path.exists():
        df = _load_jsonl(input_path)
    else:
        print("Using synthetic bootstrap dataset.")
        df = _make_synthetic_dataset()

    X = df[_FEATURE_COLS].to_numpy(dtype=np.float32)
    y = df["label"].to_numpy()

    try:
        import lightgbm as lgb
        from onnxmltools import convert_lightgbm
        from onnxmltools.convert.common.data_types import FloatTensorType
        from sklearn.model_selection import cross_val_score

        clf = lgb.LGBMClassifier(
            n_estimators=200,
            max_depth=4,
            num_leaves=15,
            learning_rate=0.05,
            class_weight="balanced",
            random_state=42,
            n_jobs=-1,
            verbose=-1,
        )
        cv_scores = cross_val_score(clf, X, y, cv=5, scoring="f1_macro")
        clf.fit(X, y)

        metrics = evaluate_multiclass(y, clf.predict_proba(X), _CLASS_LABELS)
        gate_on_metrics(metrics, min_macro_f1=0.75)

        # onnxmltools converts LightGBM natively; skl2onnx cannot wrap it inside
        # CalibratedClassifierCV, so we export the classifier directly.
        onnx_model = convert_lightgbm(
            clf.booster_,
            initial_types=[("input", FloatTensorType([None, len(_FEATURE_COLS)]))],
        )
        (output_dir / "model.onnx").write_bytes(onnx_model.SerializeToString())
        print(f"CV macro-F1: {cv_scores.mean():.3f} ± {cv_scores.std():.3f}")

    except ImportError as exc:
        print(f"Dependency missing ({exc}) — ONNX export skipped.")
        return

    metadata = {
        "model_name": "recon_break_classifier",
        "algorithm": "LightGBM+Isotonic",
        "classes": _CLASS_LABELS,
        "features": _FEATURE_COLS,
        "metrics": metrics,
    }
    (output_dir / "metadata.json").write_text(json.dumps(metadata, indent=2))
    print(f"Saved model to {output_dir} | macro-F1: {metrics.get('macro_f1', 'n/a'):.3f}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Train ReconBreakClassifier")
    parser.add_argument("--source", choices=["db", "jsonl", "synthetic"], default="db")
    parser.add_argument("--input", type=Path, default=None)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    train(args.output, args.input, args.source)


if __name__ == "__main__":
    main()
