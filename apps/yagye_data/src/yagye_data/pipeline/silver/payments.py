"""Silver ETL: payment_attempt events.

Reads Bronze NDJSON for the given time window, deduplicates on (event_id),
casts types, and writes partitioned Silver Parquet.

Field notes:
  - payment_id comes from the envelope top-level `aggregate_id` (the internal
    payment UUID). The payload has `public_id` (customer-facing code) which is
    a different identifier. We use aggregate_id so joins to other event types
    on the same aggregate work cleanly.
  - method / provider_code / network / latency_ms come from payload fields.
  - customer_msisdn is the payload field name (not 'msisdn').
"""

from datetime import datetime
from pathlib import Path

import duckdb

from yagye_data.config import settings
from yagye_data.shared.duckdb_client import get_connection
from yagye_data.shared.logging import get_logger
from yagye_data.shared.s3_client import s3_uri

logger = get_logger(__name__)

# Envelope top-level fields present in every Bronze NDJSON row:
#   event_id, event_type, merchant_id, aggregate_id, occurred_at, payload, mode


def run(
    window_start: datetime,
    window_end: datetime,
    *,
    con: duckdb.DuckDBPyConnection | None = None,
) -> None:
    ds = window_start.strftime("%Y-%m-%d")
    bronze_glob = s3_uri(settings.bronze_bucket, f"events/dt={ds}/payment*.ndjson")
    silver_prefix = s3_uri(settings.silver_bucket, f"payments/dt={ds}/part.parquet")

    logger.info("silver.payments.start", date=ds, bronze_glob=bronze_glob)

    if silver_prefix.startswith("/"):
        Path(silver_prefix).parent.mkdir(parents=True, exist_ok=True)

    con = con if con is not None else get_connection()

    # Bronze is NDJSON (written by DataLakeIngestionWorker in yagye_core).
    # read_ndjson_auto() handles schema inference; nested `payload` object
    # is read as a DuckDB JSON type and extracted with json_extract_string().
    result = con.execute(f"""
        COPY (
            WITH raw AS (
                SELECT *
                FROM read_ndjson_auto('{bronze_glob}', union_by_name = true, ignore_errors = true)
                WHERE occurred_at::TIMESTAMPTZ >= TIMESTAMPTZ '{window_start.isoformat()}'
                  AND occurred_at::TIMESTAMPTZ <  TIMESTAMPTZ '{window_end.isoformat()}'
                  AND event_type IN (
                        'payment.succeeded',
                        'payment.failed',
                        'payment.indeterminate'
                      )
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
                occurred_at::TIMESTAMPTZ                            AS occurred_at,
                merchant_id::UUID                                   AS merchant_id,
                aggregate_id::UUID                                  AS payment_id,
                correlation_id                                      AS correlation_id,
                TRY_CAST(json_extract(payload, '$.amount') AS BIGINT)
                                                                    AS amount_minor,
                json_extract_string(payload, '$.currency')          AS currency,
                json_extract_string(payload, '$.method')            AS method,
                json_extract_string(payload, '$.provider_code')     AS provider_code,
                TRY_CAST(json_extract(payload, '$.latency_ms') AS INT)
                                                                    AS latency_ms,
                json_extract_string(payload, '$.network')           AS network,
                mode                                                AS mode,
                sha256(NULLIF(json_extract_string(payload, '$.customer_msisdn'), ''))
                                                                    AS customer_msisdn_hash,
                payload::VARCHAR                                    AS raw_payload,
                '{ds}'::DATE                                        AS dt
            FROM deduped
            WHERE _rn = 1
        )
        TO '{silver_prefix}'
        (FORMAT parquet, COMPRESSION zstd, ROW_GROUP_SIZE 100000)
    """).fetchone()

    logger.info("silver.payments.done", date=ds, rows=result[0] if result else 0)
