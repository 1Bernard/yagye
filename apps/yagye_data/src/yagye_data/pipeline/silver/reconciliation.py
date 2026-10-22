"""Silver ETL: reconciliation events.

Core emits these reconciliation event types:

  reconciliation.run.completed
    run_id, public_id, kind, matched_count, break_count,
    matched_value, break_value

  reconciliation.report.ingested
    report_id, provider_id, mode, report_date, line_count,
    quarantined_count, reported_total, currency

  reconciliation.adjustment.proposed
    approval_id, break_id, proposed_by, proposed_action

  reconciliation.adjustment.approved
    approval_id, break_id, proposed_by, approved_by

  reconciliation.adjustment.rejected
    approval_id, break_id, proposed_by, rejected_by, rejected_reason

Silver reconciliation holds one row per event, typed. Gold ops_mart reads this
to compute reconciliation_summary (break rates, adjustment cycle times).
"""

from datetime import datetime

from yagye_data.config import settings
from yagye_data.shared.duckdb_client import get_connection
from yagye_data.shared.logging import get_logger
from yagye_data.shared.s3_client import s3_uri

logger = get_logger(__name__)

_RECON_EVENTS = (
    "reconciliation.run.completed",
    "reconciliation.report.ingested",
    "reconciliation.adjustment.proposed",
    "reconciliation.adjustment.approved",
    "reconciliation.adjustment.rejected",
)


def run(window_start: datetime, window_end: datetime) -> None:
    ds = window_start.strftime("%Y-%m-%d")
    bronze_glob = s3_uri(settings.bronze_bucket, f"events/dt={ds}/reconciliation*.ndjson")
    silver_prefix = s3_uri(settings.silver_bucket, f"reconciliation/dt={ds}/part.parquet")

    logger.info("silver.reconciliation.start", date=ds)

    event_list = ", ".join(f"'{e}'" for e in _RECON_EVENTS)
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
                occurred_at::TIMESTAMPTZ                                     AS occurred_at,
                merchant_id::UUID                                            AS merchant_id,

                -- reconciliation.run.completed fields
                json_extract_string(payload, '$.run_id')::UUID               AS run_id,
                json_extract_string(payload, '$.kind')                       AS run_kind,
                TRY_CAST(json_extract(payload, '$.matched_count') AS BIGINT) AS matched_count,
                TRY_CAST(json_extract(payload, '$.break_count')   AS BIGINT) AS break_count,
                TRY_CAST(json_extract(payload, '$.matched_value') AS BIGINT) AS matched_value_minor,
                TRY_CAST(json_extract(payload, '$.break_value')   AS BIGINT) AS break_value_minor,

                -- reconciliation.report.ingested fields
                json_extract_string(payload, '$.report_id')::UUID            AS report_id,
                TRY_CAST(json_extract(payload, '$.line_count') AS INT)       AS line_count,
                TRY_CAST(json_extract(payload, '$.quarantined_count') AS INT) AS quarantined_count,
                TRY_CAST(json_extract(payload, '$.reported_total') AS BIGINT) AS reported_total_minor,
                json_extract_string(payload, '$.currency')                   AS currency,

                -- reconciliation.adjustment.* fields
                json_extract_string(payload, '$.approval_id')::UUID          AS approval_id,
                json_extract_string(payload, '$.break_id')::UUID             AS break_id,
                json_extract_string(payload, '$.proposed_action')            AS proposed_action,

                payload::VARCHAR                                             AS raw_payload,
                '{ds}'::DATE                                                 AS dt
            FROM deduped
            WHERE _rn = 1
        )
        TO '{silver_prefix}'
        (FORMAT parquet, COMPRESSION zstd)
    """)

    logger.info("silver.reconciliation.done", date=ds)
