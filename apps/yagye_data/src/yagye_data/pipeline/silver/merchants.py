"""Silver ETL: merchant lifecycle events.

Core emits these merchant event types and their payload fields:

  merchant.registered   merchant_code, legal_name, trading_name,
                        country, default_currency
  merchant.approved     merchant_code, approved_by
  merchant.suspended    merchant_code, suspended_by
  merchant.reinstated   merchant_code, reinstated_by

Note: kyb_tier and activity_state are NOT present in any published merchant
event. Gold's merchant dimension derives activity_state from the sequence of
suspended/reinstated events, not from a point-in-time field.
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
                occurred_at::TIMESTAMPTZ                        AS occurred_at,
                merchant_id::UUID                               AS merchant_id,

                -- Present in all merchant events
                json_extract_string(payload, '$.merchant_code') AS merchant_code,

                -- merchant.registered only
                json_extract_string(payload, '$.legal_name')    AS legal_name,
                json_extract_string(payload, '$.trading_name')  AS trading_name,
                json_extract_string(payload, '$.country')       AS country,
                json_extract_string(payload, '$.default_currency') AS default_currency,

                -- Actor fields (present only in specific event types, NULL otherwise)
                json_extract_string(payload, '$.approved_by')   AS approved_by,
                json_extract_string(payload, '$.suspended_by')  AS suspended_by,
                json_extract_string(payload, '$.reinstated_by') AS reinstated_by,

                payload::VARCHAR                                AS raw_payload,
                '{ds}'::DATE                                    AS dt
            FROM deduped
            WHERE _rn = 1
        )
        TO '{silver_prefix}'
        (FORMAT parquet, COMPRESSION zstd)
    """)

    logger.info("silver.merchants.done", date=ds)
