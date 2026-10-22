"""Provider health features for the routing predictor.

Features are derived from Gold provider_health_hourly Parquet.
The same feature SQL is used at training (here) and at serving (yagye_scoring).
"""

import duckdb

from yagye_data.config import settings
from yagye_data.shared.s3_client import s3_uri


def build_features(
    con: duckdb.DuckDBPyConnection,
    training_window_days: int = 90,
) -> duckdb.DuckDBPyRelation:
    """Return a relation of per-provider hourly features for the routing predictor.

    Columns: provider_code, hour_bucket, success_rate, p50_latency_ms,
             p95_latency_ms, rolling_24h_success_rate, attempt_count, dt
    """
    gold_glob = s3_uri(settings.gold_bucket, "provider_health_hourly/**/*.parquet")
    return con.sql(f"""
        WITH base AS (
            SELECT *
            FROM read_parquet('{gold_glob}', hive_partitioning = true)
            WHERE dt >= CURRENT_DATE - INTERVAL '{training_window_days} days'
        )
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
            ) AS rolling_24h_success_rate,
            dt
        FROM base
        ORDER BY provider_code, hour_bucket
    """)
