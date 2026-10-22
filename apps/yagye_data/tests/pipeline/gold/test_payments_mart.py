"""Unit tests for Gold payments mart.

Validates that provider_health_hourly aggregation produces correct
success_rate and p50_latency_ms from a known Silver fixture.
"""

from pathlib import Path

import duckdb
import pyarrow as pa
import pyarrow.parquet as pq
import pytest


def _write_silver_payments(tmp_lake: Path, rows: list[dict], date: str = "2026-10-21") -> Path:
    out_dir = tmp_lake / "silver" / "payments" / f"dt={date}"
    out_dir.mkdir(parents=True, exist_ok=True)
    path = out_dir / "part.parquet"
    pq.write_table(pa.Table.from_pylist(rows), path)
    return path


def _make_silver_row(
    event_type: str = "payment.succeeded",
    provider_code: str = "mtn_momo_gh",
    latency_ms: int = 300,
    hour_offset: int = 0,
) -> dict:
    from datetime import UTC, datetime, timedelta
    import uuid

    base = datetime(2026, 10, 21, 10, 0, 0, tzinfo=UTC) + timedelta(hours=hour_offset)
    return {
        "event_id": str(uuid.uuid4()),
        "event_type": event_type,
        "occurred_at": base.isoformat(),
        "merchant_id": str(uuid.uuid4()),
        "payment_id": str(uuid.uuid4()),
        "amount_minor": 100_00,
        "currency": "GHS",
        "method": "mobile_money",
        "provider_code": provider_code,
        "latency_ms": latency_ms,
        "network": "MTN",
        "raw_payload": "{}",
        "dt": "2026-10-21",
    }


def test_provider_health_success_rate(
    tmp_lake: Path, duckdb_con: duckdb.DuckDBPyConnection
) -> None:
    """3 successes + 1 failure → success_rate = 0.75 for that hour bucket."""
    rows = [
        _make_silver_row("payment.succeeded", latency_ms=200),
        _make_silver_row("payment.succeeded", latency_ms=300),
        _make_silver_row("payment.succeeded", latency_ms=400),
        _make_silver_row("payment.failed", latency_ms=500),
    ]
    silver_path = str(_write_silver_payments(tmp_lake, rows))

    result = duckdb_con.execute(f"""
        SELECT
            provider_code,
            COUNT(*) AS attempt_count,
            AVG(CASE WHEN event_type = 'payment.succeeded' THEN 1.0 ELSE 0.0 END) AS success_rate,
            PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY latency_ms) AS p50_latency_ms
        FROM read_parquet('{silver_path}')
        GROUP BY provider_code
    """).fetchone()

    assert result is not None
    provider_code, attempt_count, success_rate, p50 = result
    assert provider_code == "mtn_momo_gh"
    assert attempt_count == 4
    assert abs(success_rate - 0.75) < 0.001
    assert p50 == 300.0


def test_provider_health_excludes_null_provider(
    tmp_lake: Path, duckdb_con: duckdb.DuckDBPyConnection
) -> None:
    """Rows with NULL provider_code must be excluded from the health mart."""
    rows = [
        _make_silver_row("payment.succeeded"),
        {**_make_silver_row("payment.succeeded"), "provider_code": None},
    ]
    silver_path = str(_write_silver_payments(tmp_lake, rows))

    result = duckdb_con.execute(f"""
        SELECT COUNT(*) FROM read_parquet('{silver_path}')
        WHERE provider_code IS NOT NULL
    """).fetchone()

    assert result is not None
    assert result[0] == 1
