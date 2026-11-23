"""
Extract reconciliation break features from Core DB.

The DB only has 'missing_on_right' (745) and 'missing_on_left' (9) labels —
the other classes (timing_difference, fee_discrepancy, amount_mismatch) must be
synthesised.  This module returns real DB rows augmented with synthetic rows so
the classifier can train on all four classes.
"""

from __future__ import annotations

import logging
import random

import numpy as np
import pandas as pd

from yagye_data.config import settings

logger = logging.getLogger(__name__)

# DB classes the query maps directly to classifier classes
_DB_CLASS_MAP = {
    "missing_on_right": "missing_on_right",
    "missing_on_left": "missing_on_right",  # treat left as equivalent for classifier
}

_PG_SQL = """
SELECT
    public_id,
    classification,
    COALESCE(difference, 0)         AS difference,
    COALESCE(expected_amount, 0)    AS expected_amount,
    COALESCE(actual_amount, 0)      AS actual_amount,
    right_ref IS NOT NULL           AS has_right_ref,
    detected_at
FROM reconciliation_breaks
WHERE mode = 'simulation'
  AND classification IN ('missing_on_right', 'missing_on_left')
"""


def _build_features(
    difference: int,
    expected_amount: int,
    actual_amount: int,
    age_hours: float,
    has_right_ref: bool,
    settlement_offset_days: int = 0,
) -> dict:
    abs_delta = abs(difference)
    # Use the larger of expected/actual as the reference to avoid division by zero
    # when one side is 0 (e.g. missing_on_left has expected_amount=0).
    reference = max(expected_amount, actual_amount, 1)
    relative_delta = abs_delta / reference
    return {
        "amount_delta_minor": difference,
        "abs_delta_minor": abs_delta,
        "relative_delta": min(relative_delta, 1.0),  # cap at 1.0 for missing breaks
        "age_hours": age_hours,
        "has_right_ref": int(has_right_ref),
        "settlement_offset_days": settlement_offset_days,
    }


def _make_synthetic_rows(n_per_class: int = 300, seed: int = 42) -> pd.DataFrame:
    """Generate synthetic rows for the under-represented classifier classes."""
    rng = random.Random(seed)
    rows = []

    for _ in range(n_per_class):
        # timing_difference: amounts match, no delta, old break, has right ref
        age = rng.uniform(25.0, 72.0)
        amt = rng.randint(500, 500_00)
        rows.append(
            {
                **_build_features(0, amt, amt, age, True, rng.randint(0, 2)),
                "label": "timing_difference",
            }
        )

    for _ in range(n_per_class):
        # fee_discrepancy: tiny delta (≤100), has right ref
        delta = rng.randint(1, 100)
        amt = rng.randint(500, 500_00)
        rows.append(
            {
                **_build_features(delta, amt, amt - delta, rng.uniform(0.5, 48.0), True, rng.randint(0, 1)),
                "label": "fee_discrepancy",
            }
        )

    for _ in range(n_per_class):
        # amount_mismatch: meaningful delta, has right ref
        amt = rng.randint(500, 500_00)
        delta = rng.randint(101, amt // 2)
        rows.append(
            {
                **_build_features(delta, amt, amt - delta, rng.uniform(0.5, 36.0), True, rng.randint(0, 2)),
                "label": "amount_mismatch",
            }
        )

    return pd.DataFrame(rows)


def load_recon_features(n_synthetic_per_class: int = 300) -> pd.DataFrame:
    """Return a DataFrame of break features + labels from Core DB + synthetic."""
    import duckdb

    escaped = _PG_SQL.replace("'", "''")

    con = duckdb.connect()
    try:
        con.execute("LOAD postgres;")
        con.execute(
            f"ATTACH '{settings.database_url}' AS core (TYPE POSTGRES, READ_ONLY);"
        )
        raw = con.execute(
            f"FROM postgres_query('core', '{escaped}')"
        ).df()
    finally:
        con.close()

    now = pd.Timestamp.now("UTC")
    real_rows = []
    for _, row in raw.iterrows():
        detected = pd.to_datetime(row["detected_at"], utc=True)
        age_hours = max(0.0, (now - detected).total_seconds() / 3600)
        label = _DB_CLASS_MAP.get(str(row["classification"]), "missing_on_right")
        real_rows.append(
            {
                **_build_features(
                    int(row["difference"]),
                    int(row["expected_amount"]),
                    int(row["actual_amount"]),
                    age_hours,
                    bool(row["has_right_ref"]),
                    0,
                ),
                "label": label,
            }
        )

    real_df = pd.DataFrame(real_rows)
    synth_df = _make_synthetic_rows(n_synthetic_per_class)

    df = pd.concat([real_df, synth_df], ignore_index=True)

    label_counts = df["label"].value_counts().to_dict()
    logger.info(
        "recon_from_db: %d total rows (real: %d, synthetic: %d) — %s",
        len(df),
        len(real_df),
        len(synth_df),
        label_counts,
    )
    return df
