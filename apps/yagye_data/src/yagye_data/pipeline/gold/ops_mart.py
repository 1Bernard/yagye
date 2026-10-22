"""Gold ETL: ops mart — settlement and reconciliation aggregates.

Outputs:
  - gold/settlement_daily/          — per-merchant daily settlement summary
  - gold/reconciliation_summary/    — match/unmatch rates by merchant + date
"""

from datetime import datetime

from yagye_data.config import settings
from yagye_data.shared.duckdb_client import get_connection
from yagye_data.shared.logging import get_logger
from yagye_data.shared.s3_client import s3_uri

logger = get_logger(__name__)


def run(window_start: datetime, window_end: datetime) -> None:
    ds = window_start.strftime("%Y-%m-%d")

    logger.info("gold.ops_mart.start", date=ds)

    con = get_connection()

    # ── Settlement daily ───────────────────────────────────────────────────────
    settlement_silver = s3_uri(settings.silver_bucket, f"settlements/dt={ds}/part.parquet")
    settlement_out = s3_uri(settings.gold_bucket, f"settlement_daily/dt={ds}/part.parquet")
    con.execute(f"""
        COPY (
            SELECT
                merchant_id,
                currency,
                provider_code,
                '{ds}'::DATE                                       AS dt,
                COUNT(*)                                           AS batch_count,
                SUM(gross_amount_minor)                            AS total_gross_minor,
                SUM(fee_amount_minor)                              AS total_fee_minor,
                SUM(net_amount_minor)                              AS total_net_minor,
                SUM(CASE WHEN event_type = 'settlement_batch.completed' THEN 1 ELSE 0 END)
                                                                   AS completed_count,
                SUM(CASE WHEN event_type = 'settlement_batch.failed' THEN 1 ELSE 0 END)
                                                                   AS failed_count
            FROM read_parquet('{settlement_silver}')
            WHERE occurred_at >= TIMESTAMPTZ '{window_start.isoformat()}'
              AND occurred_at <  TIMESTAMPTZ '{window_end.isoformat()}'
            GROUP BY 1, 2, 3, 4
        )
        TO '{settlement_out}'
        (FORMAT parquet, COMPRESSION zstd)
    """)

    # ── Reconciliation summary ─────────────────────────────────────────────────
    recon_silver = s3_uri(settings.silver_bucket, f"reconciliation/dt={ds}/part.parquet")
    recon_out = s3_uri(settings.gold_bucket, f"reconciliation_summary/dt={ds}/part.parquet")
    con.execute(f"""
        COPY (
            SELECT
                merchant_id,
                currency,
                '{ds}'::DATE                                          AS dt,
                COUNT(*)                                              AS total_events,
                SUM(CASE WHEN event_type = 'reconciliation.matched' THEN 1 ELSE 0 END)
                                                                      AS matched_count,
                SUM(CASE WHEN event_type = 'reconciliation.unmatched' THEN 1 ELSE 0 END)
                                                                      AS unmatched_count,
                SUM(CASE WHEN event_type = 'reconciliation.disputed' THEN 1 ELSE 0 END)
                                                                      AS disputed_count,
                AVG(CASE WHEN event_type = 'reconciliation.matched' THEN 1.0 ELSE 0.0 END)
                                                                      AS match_rate
            FROM read_parquet('{recon_silver}')
            WHERE occurred_at >= TIMESTAMPTZ '{window_start.isoformat()}'
              AND occurred_at <  TIMESTAMPTZ '{window_end.isoformat()}'
            GROUP BY 1, 2, 3
        )
        TO '{recon_out}'
        (FORMAT parquet, COMPRESSION zstd)
    """)

    logger.info("gold.ops_mart.done", date=ds)
