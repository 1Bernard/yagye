"""Customer (MSISDN) risk features for the risk scorer.

Derived from the cross-merchant customer_risk_global_hourly Gold table.
"""

import duckdb

from yagye_data.config import settings
from yagye_data.shared.s3_client import s3_uri


def build_features(
    con: duckdb.DuckDBPyConnection,
    training_window_days: int = 90,
) -> duckdb.DuckDBPyRelation:
    """Return per-MSISDN hourly risk features.

    Columns: msisdn, hour_bucket, merchant_count, attempt_count,
             failure_rate, rolling_24h_failure_rate, dt
    """
    gold_glob = s3_uri(settings.gold_bucket, "customer_risk_global_hourly/**/*.parquet")
    return con.sql(f"""
        WITH base AS (
            SELECT *
            FROM read_parquet('{gold_glob}', hive_partitioning = true)
            WHERE dt >= CURRENT_DATE - INTERVAL '{training_window_days} days'
        )
        SELECT
            msisdn,
            hour_bucket,
            merchant_count,
            attempt_count,
            failure_rate,
            AVG(failure_rate) OVER (
                PARTITION BY msisdn
                ORDER BY hour_bucket
                ROWS BETWEEN 23 PRECEDING AND CURRENT ROW
            ) AS rolling_24h_failure_rate,
            dt
        FROM base
        ORDER BY msisdn, hour_bucket
    """)
