"""Gold ETL: payments fact mart + provider health dimension.

Outputs:
  - gold/provider_health_hourly/  — hourly success rate + latency per provider
      (primary input for the routing predictor and circuit breaker)
  - gold/payment_facts/           — per-payment grain with all dimensional keys
"""

from datetime import datetime

from yagye_data.config import settings
from yagye_data.shared.duckdb_client import get_connection
from yagye_data.shared.logging import get_logger
from yagye_data.shared.s3_client import s3_uri

logger = get_logger(__name__)


def run(window_start: datetime, window_end: datetime) -> None:
    ds = window_start.strftime("%Y-%m-%d")
    silver_glob = s3_uri(settings.silver_bucket, f"payments/dt={ds}/part.parquet")

    logger.info("gold.payments_mart.start", date=ds)

    con = get_connection()

    # ── Provider health (primary ML input) ────────────────────────────────────
    provider_health_out = s3_uri(
        settings.gold_bucket, f"provider_health_hourly/dt={ds}/part.parquet"
    )
    con.execute(f"""
        COPY (
            SELECT
                DATE_TRUNC('hour', occurred_at)              AS hour_bucket,
                provider_code,
                COUNT(*)                                     AS attempt_count,
                SUM(CASE WHEN event_type = 'payment.succeeded' THEN 1 ELSE 0 END)
                                                             AS success_count,
                AVG(CASE WHEN event_type = 'payment.succeeded' THEN 1.0 ELSE 0.0 END)
                                                             AS success_rate,
                PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY latency_ms)
                                                             AS p50_latency_ms,
                PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY latency_ms)
                                                             AS p95_latency_ms,
                AVG(latency_ms)                              AS avg_latency_ms,
                '{ds}'::DATE                                 AS dt
            FROM read_parquet('{silver_glob}')
            WHERE occurred_at >= TIMESTAMPTZ '{window_start.isoformat()}'
              AND occurred_at <  TIMESTAMPTZ '{window_end.isoformat()}'
              AND provider_code IS NOT NULL
            GROUP BY 1, 2
        )
        TO '{provider_health_out}'
        (FORMAT parquet, COMPRESSION zstd, ROW_GROUP_SIZE 50000)
    """)

    # ── Payment facts (wide grain for general analytics) ──────────────────────
    payment_facts_out = s3_uri(settings.gold_bucket, f"payment_facts/dt={ds}/part.parquet")
    con.execute(f"""
        COPY (
            SELECT
                event_id,
                event_type,
                occurred_at,
                merchant_id,
                payment_id,
                amount_minor,
                currency,
                method,
                provider_code,
                latency_ms,
                network,
                '{ds}'::DATE AS dt
            FROM read_parquet('{silver_glob}')
            WHERE occurred_at >= TIMESTAMPTZ '{window_start.isoformat()}'
              AND occurred_at <  TIMESTAMPTZ '{window_end.isoformat()}'
        )
        TO '{payment_facts_out}'
        (FORMAT parquet, COMPRESSION zstd, ROW_GROUP_SIZE 100000)
    """)

    logger.info("gold.payments_mart.done", date=ds)
