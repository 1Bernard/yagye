"""
Extract per-MSISDN velocity features from Core DB (simulation payments).

Returns one row per MSISDN using their peak 1-hour window stats.
Label heuristic (for ROC-AUC gating only — IsolationForest is unsupervised):
  anomalous = 1 if max_1h_count >= 10 OR failure_rate >= 0.90
  normal    = 0 otherwise
"""

from __future__ import annotations

import logging

import pandas as pd

from yagye_data.config import settings

logger = logging.getLogger(__name__)

_BURST_THRESHOLD = 10
_FAIL_RATE_THRESHOLD = 0.90

# Executed in Postgres SQL dialect via postgres_query so JSONB operators work.
_PG_SQL = """
WITH raw AS (
    SELECT
        metadata->>'msisdn_hash'          AS msisdn_hash,
        merchant_id,
        method,
        amount                            AS amount_minor,
        state,
        inserted_at,
        date_trunc('hour', inserted_at)   AS hour_bucket
    FROM payments
    WHERE mode = 'simulation'
      AND metadata->>'msisdn_hash' IS NOT NULL
),
hourly AS (
    SELECT
        msisdn_hash,
        hour_bucket,
        COUNT(*)                                              AS cnt_1h,
        COUNT(*) FILTER (WHERE state = 'failed')             AS fail_cnt_1h
    FROM raw
    GROUP BY msisdn_hash, hour_bucket
),
peak_hour AS (
    SELECT
        msisdn_hash,
        MAX(cnt_1h)       AS max_attempt_1h,
        MAX(fail_cnt_1h)  AS max_fail_1h
    FROM hourly
    GROUP BY msisdn_hash
),
totals AS (
    SELECT
        msisdn_hash,
        COUNT(*)                                                                     AS txn_count_24h,
        COUNT(*) FILTER (WHERE state = 'failed')                                    AS fail_count_24h,
        COUNT(DISTINCT merchant_id)                                                  AS distinct_merchant_count,
        AVG(amount_minor)                                                            AS avg_amount_minor,
        EXTRACT(HOUR FROM MIN(inserted_at))                                         AS hour_of_day,
        EXTRACT(DOW  FROM MIN(inserted_at))                                         AS day_of_week,
        MAX(CASE WHEN method = 'mobile_money' THEN 1 ELSE 0 END)                   AS is_momo,
        COUNT(*) FILTER (WHERE state = 'failed')::FLOAT / NULLIF(COUNT(*), 0)      AS failure_rate
    FROM raw
    GROUP BY msisdn_hash
)
SELECT
    t.msisdn_hash,
    p.max_attempt_1h                AS attempt_count_1h,
    p.max_fail_1h                   AS fail_count_1h,
    t.txn_count_24h,
    t.fail_count_24h,
    COALESCE(t.failure_rate, 0)     AS failure_rate,
    t.distinct_merchant_count,
    t.avg_amount_minor              AS amount_minor,
    t.is_momo,
    t.hour_of_day,
    t.day_of_week
FROM totals t
JOIN peak_hour p ON t.msisdn_hash = p.msisdn_hash
ORDER BY p.max_attempt_1h DESC
"""


def load_velocity_features() -> pd.DataFrame:
    """Return a DataFrame of velocity features + heuristic label from Core DB."""
    import duckdb

    escaped = _PG_SQL.replace("'", "''")

    con = duckdb.connect()
    try:
        con.execute("LOAD postgres;")
        con.execute(
            f"ATTACH '{settings.database_url}' AS core (TYPE POSTGRES, READ_ONLY);"
        )
        df = con.execute(
            f"FROM postgres_query('core', '{escaped}')"
        ).df()
    finally:
        con.close()

    df = df.astype(
        {
            "attempt_count_1h": float,
            "fail_count_1h": float,
            "txn_count_24h": float,
            "fail_count_24h": float,
            "failure_rate": float,
            "distinct_merchant_count": float,
            "amount_minor": float,
            "is_momo": float,
            "hour_of_day": float,
            "day_of_week": float,
        }
    )

    # Heuristic label — used only for gate evaluation, not for training
    df["label"] = (
        (df["attempt_count_1h"] >= _BURST_THRESHOLD)
        | (df["failure_rate"] >= _FAIL_RATE_THRESHOLD)
    ).astype(int)

    logger.info(
        "velocity_from_db: %d MSISDNs loaded (%d anomalous, %d normal)",
        len(df),
        int(df["label"].sum()),
        int((df["label"] == 0).sum()),
    )
    return df
