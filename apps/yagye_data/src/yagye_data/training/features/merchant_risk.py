"""Merchant risk features for the risk scorer and churn predictor."""

import duckdb

from yagye_data.config import settings
from yagye_data.shared.s3_client import s3_uri


def build_features(
    con: duckdb.DuckDBPyConnection,
    training_window_days: int = 180,
) -> duckdb.DuckDBPyRelation:
    """Return per-merchant daily aggregated risk features.

    Columns: merchant_id, dt, success_rate, failure_count, gross_volume_minor,
             rolling_7d_failure_rate, days_since_first_txn, method_count
    """
    gold_glob = s3_uri(settings.gold_bucket, "merchant_risk_daily/**/*.parquet")
    return con.sql(f"""
        WITH base AS (
            SELECT *
            FROM read_parquet('{gold_glob}', hive_partitioning = true)
            WHERE dt >= CURRENT_DATE - INTERVAL '{training_window_days} days'
        )
        SELECT
            merchant_id,
            dt,
            success_rate,
            failure_count,
            total_attempts,
            gross_volume_minor,
            method_count,
            AVG(1.0 - success_rate) OVER (
                PARTITION BY merchant_id
                ORDER BY dt
                ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
            ) AS rolling_7d_failure_rate,
            DATEDIFF('day', MIN(dt) OVER (PARTITION BY merchant_id), dt)
                AS days_since_first_txn
        FROM base
        ORDER BY merchant_id, dt
    """)
