"""Silver ETL: settlement events."""

from datetime import datetime

from yagye_data.config import settings
from yagye_data.shared.duckdb_client import get_connection
from yagye_data.shared.logging import get_logger
from yagye_data.shared.s3_client import s3_uri

logger = get_logger(__name__)


def run(window_start: datetime, window_end: datetime) -> None:
    ds = window_start.strftime("%Y-%m-%d")
    bronze_glob = s3_uri(settings.bronze_bucket, f"events/dt={ds}/settlement*.ndjson")
    silver_prefix = s3_uri(settings.silver_bucket, f"settlements/dt={ds}/part.parquet")

    logger.info("silver.settlements.start", date=ds)

    con = get_connection()
    con.execute(f"""
        COPY (
            WITH raw AS (
                SELECT *
                FROM read_ndjson_auto('{bronze_glob}', union_by_name = true, ignore_errors = true)
                WHERE occurred_at::TIMESTAMPTZ >= TIMESTAMPTZ '{window_start.isoformat()}'
                  AND occurred_at::TIMESTAMPTZ <  TIMESTAMPTZ '{window_end.isoformat()}'
                  AND event_type IN (
                        'settlement_batch.created',
                        'settlement_batch.dispatched',
                        'settlement_batch.completed',
                        'settlement_batch.failed'
                      )
            ),
            deduped AS (
                SELECT *,
                       ROW_NUMBER() OVER (PARTITION BY event_id ORDER BY occurred_at) AS _rn
                FROM raw
            )
            SELECT
                event_id,
                event_type,
                occurred_at::TIMESTAMPTZ                                AS occurred_at,
                merchant_id::UUID                                       AS merchant_id,
                json_extract_string(payload, '$.batch_id')::UUID        AS batch_id,
                TRY_CAST(json_extract(payload, '$.gross_amount') AS BIGINT)
                                                                        AS gross_amount_minor,
                TRY_CAST(json_extract(payload, '$.fee_amount')   AS BIGINT)
                                                                        AS fee_amount_minor,
                TRY_CAST(json_extract(payload, '$.net_amount')   AS BIGINT)
                                                                        AS net_amount_minor,
                json_extract_string(payload, '$.currency')              AS currency,
                json_extract_string(payload, '$.provider_code')         AS provider_code,
                payload::VARCHAR                                        AS raw_payload,
                '{ds}'::DATE                                            AS dt
            FROM deduped
            WHERE _rn = 1
        )
        TO '{silver_prefix}'
        (FORMAT parquet, COMPRESSION zstd, ROW_GROUP_SIZE 100000)
    """)

    logger.info("silver.settlements.done", date=ds)
