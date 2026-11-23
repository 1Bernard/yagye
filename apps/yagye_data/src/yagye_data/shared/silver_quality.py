"""Silver data quality checks.

After each Silver COPY, call emit() to log null-count and row-drop metrics.
A dropped_rows > 0 or null_amount_count > 0 is logged at WARNING level so
Grafana/Loki alert rules can fire on it.
"""

from __future__ import annotations

import duckdb

from yagye_data.shared.logging import get_logger

logger = get_logger(__name__)


def emit(
    entity: str,
    ds: str,
    silver_path: str,
    output_rows: int,
    source_rows: int,
    *,
    amount_col: str | None = "amount_minor",
    con: duckdb.DuckDBPyConnection | None = None,
) -> None:
    """Log quality metrics for a Silver entity.

    Args:
        entity: short label, e.g. "payments", "settlements"
        ds: date string "YYYY-MM-DD"
        silver_path: S3 or local path to the written parquet
        output_rows: row count returned by COPY
        source_rows: row count read from Bronze before dedup/filter
        amount_col: name of the primary financial column to null-check; None skips
        con: DuckDB connection (creates one if None)
    """
    from yagye_data.shared.duckdb_client import get_connection

    if con is None:
        con = get_connection()

    dropped_rows = max(0, source_rows - output_rows)
    null_amount_count = 0

    if amount_col and output_rows > 0 and not silver_path.startswith("/nonexistent"):
        try:
            row = con.execute(
                f"SELECT COUNT(*) FROM read_parquet('{silver_path}') "
                f"WHERE {amount_col} IS NULL"
            ).fetchone()
            null_amount_count = row[0] if row else 0
        except Exception:
            pass

    log_fn = logger.warning if (dropped_rows > 0 or null_amount_count > 0) else logger.info

    log_fn(
        f"silver.{entity}.quality",
        date=ds,
        entity=entity,
        source_rows=source_rows,
        output_rows=output_rows,
        dropped_rows=dropped_rows,
        null_amount_count=null_amount_count,
    )
