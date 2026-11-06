"""Gold ETL: payments fact mart.

Outputs:
  - gold/payment_facts/  — per-payment grain with all dimensional keys

Note: provider_health_hourly is produced by gold/provider_health.py (richer
schema with provider_kind, method, currency, failure breakdowns). Do not
write to that prefix here.
"""

from datetime import datetime
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
    ds = window_start.strftime("%Y-%m-%d")
    silver_glob = s3_uri(settings.silver_bucket, f"payments/dt={ds}/part.parquet")

    logger.info("gold.payments_mart.start", date=ds)

    con = con if con is not None else get_connection()

    # ── Payment facts (wide grain for general analytics) ──────────────────────
    payment_facts_out = s3_uri(settings.gold_bucket, f"payment_facts/dt={ds}/part.parquet")
    if payment_facts_out.startswith("/"):
        Path(payment_facts_out).parent.mkdir(parents=True, exist_ok=True)
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
            WHERE occurred_at::TIMESTAMPTZ >= TIMESTAMPTZ '{window_start.isoformat()}'
              AND occurred_at::TIMESTAMPTZ <  TIMESTAMPTZ '{window_end.isoformat()}'
              AND (mode IS NULL OR mode = 'live')
        )
        TO '{payment_facts_out}'
        (FORMAT parquet, COMPRESSION zstd, ROW_GROUP_SIZE 100000)
    """)

    logger.info("gold.payments_mart.done", date=ds)
