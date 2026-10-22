"""Silver ETL: merchant lifecycle events.

Includes merchant.registered, merchant.approved, merchant.suspended,
merchant.reinstated — used to build the SCD Type 2 merchant dimension in Gold.
"""

from datetime import datetime

from yagye_data.config import settings
from yagye_data.shared.duckdb_client import get_connection
from yagye_data.shared.logging import get_logger
from yagye_data.shared.s3_client import s3_uri

logger = get_logger(__name__)

_MERCHANT_EVENTS = (
    "merchant.registered",
    "merchant.approved",
    "merchant.suspended",
    "merchant.reinstated",
)


def run(window_start: datetime, window_end: datetime) -> None:
    ds = window_start.strftime("%Y-%m-%d")
    bronze_glob = s3_uri(settings.bronze_bucket, f"events/dt={ds}/merchant*.ndjson")
    silver_prefix = s3_uri(settings.silver_bucket, f"merchants/dt={ds}/part.parquet")

    logger.info("silver.merchants.start", date=ds)

    event_list = ", ".join(f"'{e}'" for e in _MERCHANT_EVENTS)
    con = get_connection()
    con.execute(f"""
        COPY (
            WITH raw AS (
                SELECT *
                FROM read_ndjson_auto('{bronze_glob}', union_by_name = true, ignore_errors = true)
                WHERE occurred_at::TIMESTAMPTZ >= TIMESTAMPTZ '{window_start.isoformat()}'
                  AND occurred_at::TIMESTAMPTZ <  TIMESTAMPTZ '{window_end.isoformat()}'
                  AND event_type IN ({event_list})
            ),
            deduped AS (
                SELECT *,
                       ROW_NUMBER() OVER (PARTITION BY event_id ORDER BY occurred_at) AS _rn
                FROM raw
            )
            SELECT
                event_id,
                event_type,
                occurred_at::TIMESTAMPTZ                          AS occurred_at,
                merchant_id::UUID                                 AS merchant_id,
                json_extract_string(payload, '$.merchant_code')   AS merchant_code,
                TRY_CAST(json_extract(payload, '$.kyb_tier') AS INT)
                                                                  AS kyb_tier,
                json_extract_string(payload, '$.activity_state')  AS activity_state,
                payload::VARCHAR                                  AS raw_payload,
                '{ds}'::DATE                                      AS dt
            FROM deduped
            WHERE _rn = 1
        )
        TO '{silver_prefix}'
        (FORMAT parquet, COMPRESSION zstd)
    """)

    logger.info("silver.merchants.done", date=ds)
