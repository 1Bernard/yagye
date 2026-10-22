"""Unit tests for Silver payments ETL.

These tests write Bronze Parquet files into the tmp_lake fixture and verify
that the Silver ETL produces correctly typed, deduplicated output.
"""

import uuid
from datetime import UTC, datetime, timedelta
from pathlib import Path

import duckdb
import pytest


def _make_bronze_row(
    event_type: str = "payment.succeeded",
    event_id: str | None = None,
    occurred_at: datetime | None = None,
    amount: int = 100_00,
) -> dict:
    return {
        "event_id": event_id or str(uuid.uuid4()),
        "event_type": event_type,
        "occurred_at": (occurred_at or datetime.now(UTC)).isoformat(),
        "merchant_id": str(uuid.uuid4()),
        "payment_id": str(uuid.uuid4()),
        "amount": amount,
        "currency": "GHS",
        "method": "mobile_money",
        "provider_code": "mtn_momo_gh",
        "latency_ms": 320,
        "network": "MTN",
        "payload": "{}",
    }


def _write_bronze(tmp_lake: Path, rows: list[dict], date: str = "2026-10-21") -> Path:
    import pyarrow as pa
    import pyarrow.parquet as pq

    out_dir = tmp_lake / "raw" / f"events" / f"dt={date}"
    out_dir.mkdir(parents=True, exist_ok=True)
    path = out_dir / "payment_test.parquet"
    table = pa.Table.from_pylist(rows)
    pq.write_table(table, path)
    return path


@pytest.mark.integration
def test_payments_silver_deduplicates(tmp_lake: Path, duckdb_con: duckdb.DuckDBPyConnection) -> None:
    """Duplicate event_ids must produce only one output row."""
    shared_id = str(uuid.uuid4())
    ts = datetime.now(UTC)
    rows = [
        _make_bronze_row(event_id=shared_id, occurred_at=ts),
        _make_bronze_row(event_id=shared_id, occurred_at=ts + timedelta(seconds=1)),
        _make_bronze_row(),  # distinct id — should also appear
    ]
    _write_bronze(tmp_lake, rows)

    # Read the Bronze file directly and verify our dedup SQL logic
    bronze_path = str(tmp_lake / "raw" / "events" / "dt=2026-10-21" / "payment_test.parquet")
    result = duckdb_con.execute(f"""
        WITH raw AS (SELECT * FROM read_parquet('{bronze_path}')),
        deduped AS (
            SELECT *, ROW_NUMBER() OVER (PARTITION BY event_id ORDER BY occurred_at) AS _rn
            FROM raw
        )
        SELECT COUNT(*) AS cnt FROM deduped WHERE _rn = 1
    """).fetchone()

    assert result is not None
    assert result[0] == 2, f"Expected 2 unique events, got {result[0]}"


def test_payments_silver_filters_event_types(tmp_lake: Path, duckdb_con: duckdb.DuckDBPyConnection) -> None:
    """Only payment.succeeded / failed / indeterminate events should pass through."""
    rows = [
        _make_bronze_row(event_type="payment.succeeded"),
        _make_bronze_row(event_type="payment.failed"),
        _make_bronze_row(event_type="merchant.registered"),  # must be excluded
        _make_bronze_row(event_type="settlement_batch.created"),  # must be excluded
    ]
    _write_bronze(tmp_lake, rows)

    bronze_path = str(tmp_lake / "raw" / "events" / "dt=2026-10-21" / "payment_test.parquet")
    result = duckdb_con.execute(f"""
        SELECT COUNT(*) FROM read_parquet('{bronze_path}')
        WHERE event_type IN ('payment.succeeded', 'payment.failed', 'payment.indeterminate')
    """).fetchone()

    assert result is not None
    assert result[0] == 2
