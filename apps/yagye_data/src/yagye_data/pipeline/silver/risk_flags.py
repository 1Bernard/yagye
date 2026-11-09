"""Silver ETL: payment.risk_flagged events with LLM fraud narrative enrichment.

Reads Bronze NDJSON for the given time window, deduplicates on (event_id),
casts types, enriches with LLM-generated fraud_narrative via Haiku, and
writes partitioned Silver Parquet.

The fraud_narrative column is an analyst-readable summary of why the payment
was flagged (risk signals, velocity, amount context). Used in the SAR PDF
and in the ops risk queue.
"""

from datetime import datetime
from pathlib import Path

import duckdb
import pandas as pd

from yagye_data.config import settings
from yagye_data.pipeline.silver.enrichment.payments import enrich_batch
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
    bronze_glob = s3_uri(settings.bronze_bucket, f"events/dt={ds}/payment*.ndjson")
    silver_prefix = s3_uri(settings.silver_bucket, f"risk_flags/dt={ds}/part.parquet")

    logger.info("silver.risk_flags.start", date=ds, bronze_glob=bronze_glob)

    if silver_prefix.startswith("/"):
        Path(silver_prefix).parent.mkdir(parents=True, exist_ok=True)

    con = con if con is not None else get_connection()

    df = con.execute(f"""
        WITH raw AS (
            SELECT *
            FROM read_ndjson_auto('{bronze_glob}', union_by_name = true, ignore_errors = true)
            WHERE occurred_at::TIMESTAMPTZ >= TIMESTAMPTZ '{window_start.isoformat()}'
              AND occurred_at::TIMESTAMPTZ <  TIMESTAMPTZ '{window_end.isoformat()}'
              AND event_type = 'payment.risk_flagged'
        ),
        deduped AS (
            SELECT *,
                   ROW_NUMBER() OVER (
                       PARTITION BY event_id
                       ORDER BY occurred_at
                   ) AS _rn
            FROM raw
        )
        SELECT
            event_id,
            event_type,
            occurred_at::TIMESTAMPTZ                                AS occurred_at,
            merchant_id::UUID                                       AS merchant_id,
            aggregate_id::UUID                                      AS payment_id,
            json_extract_string(payload, '$.public_id')             AS public_id,
            json_extract_string(payload, '$.risk_decision')         AS risk_decision,
            TRY_CAST(json_extract(payload, '$.risk_score') AS DOUBLE)
                                                                    AS risk_score,
            json_extract_string(payload, '$.risk_flagged_at')       AS risk_flagged_at,
            mode                                                    AS mode,
            '{ds}'::DATE                                            AS dt
        FROM deduped
        WHERE _rn = 1
    """).df()

    if df.empty:
        logger.info("silver.risk_flags.no_rows", date=ds)
        return

    # Enrich with LLM fraud narratives (Python, batch calls to Anthropic)
    records = df.to_dict(orient="records")
    enriched = enrich_batch(records)
    enriched_df = pd.DataFrame(enriched)

    # Write to Silver Parquet
    con.execute(f"""
        COPY (SELECT * FROM enriched_df)
        TO '{silver_prefix}'
        (FORMAT parquet, COMPRESSION zstd, ROW_GROUP_SIZE 100000)
    """)

    logger.info("silver.risk_flags.done", date=ds, rows=len(enriched_df))
