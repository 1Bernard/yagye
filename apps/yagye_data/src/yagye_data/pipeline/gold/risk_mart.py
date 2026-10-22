"""Gold ETL: risk mart — merchant + customer risk aggregates.

Outputs:
  - gold/merchant_risk_daily/   — per-merchant daily velocity + failure pattern features
  - gold/customer_risk_hourly/  — cross-merchant MSISDN fraud signal (§15.5 in ml-architecture)
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

    logger.info("gold.risk_mart.start", date=ds)

    con = get_connection()

    # ── Merchant risk (daily grain) ────────────────────────────────────────────
    merchant_risk_out = s3_uri(settings.gold_bucket, f"merchant_risk_daily/dt={ds}/part.parquet")
    con.execute(f"""
        COPY (
            SELECT
                merchant_id,
                '{ds}'::DATE                                  AS dt,
                COUNT(*)                                      AS total_attempts,
                SUM(CASE WHEN event_type = 'payment.succeeded' THEN 1 ELSE 0 END)
                                                              AS success_count,
                SUM(CASE WHEN event_type = 'payment.failed' THEN 1 ELSE 0 END)
                                                              AS failure_count,
                AVG(CASE WHEN event_type = 'payment.succeeded' THEN 1.0 ELSE 0.0 END)
                                                              AS success_rate,
                SUM(CASE WHEN event_type = 'payment.succeeded' THEN amount_minor ELSE 0 END)
                                                              AS gross_volume_minor,
                COUNT(DISTINCT currency)                      AS currency_count,
                COUNT(DISTINCT method)                        AS method_count
            FROM read_parquet('{silver_glob}')
            WHERE occurred_at >= TIMESTAMPTZ '{window_start.isoformat()}'
              AND occurred_at <  TIMESTAMPTZ '{window_end.isoformat()}'
            GROUP BY 1, 2
        )
        TO '{merchant_risk_out}'
        (FORMAT parquet, COMPRESSION zstd)
    """)

    # ── Customer risk (cross-merchant hourly MSISDN signal) ───────────────────
    # The payment.succeeded payload field is `customer_msisdn` (not `msisdn`).
    # This is the foundation for §15.5 (cross-merchant MSISDN fraud).
    customer_risk_out = s3_uri(
        settings.gold_bucket, f"customer_risk_global_hourly/dt={ds}/part.parquet"
    )
    con.execute(f"""
        COPY (
            SELECT
                DATE_TRUNC('hour', occurred_at)               AS hour_bucket,
                json_extract_string(raw_payload, '$.customer_msisdn') AS msisdn,
                COUNT(DISTINCT merchant_id)                   AS merchant_count,
                COUNT(*)                                      AS attempt_count,
                SUM(CASE WHEN event_type = 'payment.failed' THEN 1 ELSE 0 END)
                                                              AS failure_count,
                AVG(CASE WHEN event_type = 'payment.failed' THEN 1.0 ELSE 0.0 END)
                                                              AS failure_rate,
                '{ds}'::DATE                                  AS dt
            FROM read_parquet('{silver_glob}')
            WHERE occurred_at >= TIMESTAMPTZ '{window_start.isoformat()}'
              AND occurred_at <  TIMESTAMPTZ '{window_end.isoformat()}'
              AND json_extract_string(raw_payload, '$.customer_msisdn') IS NOT NULL
            GROUP BY 1, 2
            HAVING COUNT(*) >= 3
        )
        TO '{customer_risk_out}'
        (FORMAT parquet, COMPRESSION zstd)
    """)

    logger.info("gold.risk_mart.done", date=ds)
