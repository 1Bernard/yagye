"""Gold ETL: provider_health_hourly mart.

Aggregates Silver payment data into hourly provider performance buckets.
Produces the training features consumed by yagye_scoring routing model:
  gold/provider_health_hourly/dt=YYYY-MM-DD/part.parquet

Fields:
  hour, provider_code, provider_kind, method, currency,
  total_count, success_count, failed_count, indeterminate_count,
  success_rate, p50_latency_ms, p95_latency_ms, p99_latency_ms,
  avg_latency_ms, definite_failure_rate, retryable_error_rate
"""

from datetime import datetime, timedelta
from pathlib import Path

import duckdb

from yagye_data.config import settings
from yagye_data.shared.duckdb_client import get_connection
from yagye_data.shared.logging import get_logger
from yagye_data.shared.s3_client import s3_uri

logger = get_logger(__name__)


def run(
    window_start: datetime,
    window_end: datetime,
    *,
    con: duckdb.DuckDBPyConnection | None = None,
) -> None:
    # Aggregate over a 30-day window of Silver data so the mart covers
    # enough history for training. Re-runs are idempotent (COPY TO overwrites).
    look_back_days = 30
    first_day = window_end - timedelta(days=look_back_days)

    silver_glob = s3_uri(
        settings.silver_bucket,
        f"payments/dt=*/part.parquet",
    )
    gold_prefix = s3_uri(
        settings.gold_bucket,
        f"provider_health_hourly/dt={window_end.strftime('%Y-%m-%d')}/part.parquet",
    )

    logger.info(
        "gold.provider_health.start",
        window_end=window_end.isoformat(),
        look_back_days=look_back_days,
    )

    if gold_prefix.startswith("/"):
        Path(gold_prefix).parent.mkdir(parents=True, exist_ok=True)

    con = con if con is not None else get_connection()

    # Bail gracefully when no Silver files exist yet.
    try:
        file_count = con.execute(
            f"SELECT COUNT(*) FROM glob('{silver_glob}')"
        ).fetchone()[0]
    except Exception:
        file_count = 0

    if file_count == 0:
        logger.info("gold.provider_health.done", window_end=window_end.isoformat(), rows=0)
        return

    result = con.execute(f"""
        COPY (
            WITH silver AS (
                SELECT *
                FROM read_parquet('{silver_glob}')
                WHERE dt::VARCHAR >= '{first_day.strftime('%Y-%m-%d')}'
                  AND provider_code IS NOT NULL
            )
            SELECT
                DATE_TRUNC('hour', occurred_at::TIMESTAMPTZ) AS hour,
                provider_code,
                provider_kind,
                method,
                currency,
                COUNT(*)                                AS total_count,
                SUM(CASE WHEN event_type = 'payment.succeeded' THEN 1 ELSE 0 END)
                                                        AS success_count,
                SUM(CASE WHEN event_type = 'payment.failed' THEN 1 ELSE 0 END)
                                                        AS failed_count,
                SUM(CASE WHEN event_type = 'payment.indeterminate' THEN 1 ELSE 0 END)
                                                        AS indeterminate_count,
                ROUND(
                    SUM(CASE WHEN event_type = 'payment.succeeded' THEN 1.0 ELSE 0.0 END)
                    / NULLIF(COUNT(*), 0), 4
                )                                       AS success_rate,
                PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY latency_ms)
                                                        AS p50_latency_ms,
                PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY latency_ms)
                                                        AS p95_latency_ms,
                PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY latency_ms)
                                                        AS p99_latency_ms,
                ROUND(AVG(latency_ms), 0)               AS avg_latency_ms,
                ROUND(
                    SUM(CASE WHEN event_type = 'payment.failed' THEN 1.0 ELSE 0.0 END)
                    / NULLIF(COUNT(*), 0), 4
                )                                       AS failure_rate,
                mode
            FROM silver
            WHERE latency_ms IS NOT NULL
            GROUP BY hour, provider_code, provider_kind, method, currency, mode
            ORDER BY hour DESC, provider_code
        )
        TO '{gold_prefix}'
        (FORMAT parquet, COMPRESSION zstd, ROW_GROUP_SIZE 50000)
    """).fetchone()

    logger.info(
        "gold.provider_health.done",
        window_end=window_end.isoformat(),
        rows=result[0] if result else 0,
    )
