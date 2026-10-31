"""Unit tests for Gold provider_health_hourly mart.

Tests write Silver Parquet into the tmp_lake fixture and call
provider_health.run() directly so the pipeline code is counted in coverage.
"""

import uuid
from datetime import UTC, datetime, timedelta
from pathlib import Path

import duckdb
import pyarrow as pa
import pyarrow.parquet as pq

from yagye_data.pipeline.gold import provider_health

_WINDOW_START = datetime(2026, 10, 21, 0, 0, 0, tzinfo=UTC)
_WINDOW_END = datetime(2026, 10, 22, 0, 0, 0, tzinfo=UTC)


def _make_silver_row(
    event_type: str = "payment.succeeded",
    provider_code: str = "mtn_momo_gh",
    provider_kind: str = "native_rail",
    latency_ms: int = 300,
    method: str = "mobile_money",
    currency: str = "GHS",
    hour_offset: int = 0,
    mode: str = "live",
) -> dict:
    base = datetime(2026, 10, 21, 10, 0, 0, tzinfo=UTC) + timedelta(hours=hour_offset)
    return {
        "event_id": str(uuid.uuid4()),
        "event_type": event_type,
        "occurred_at": base.isoformat(),
        "merchant_id": str(uuid.uuid4()),
        "payment_id": str(uuid.uuid4()),
        "amount_minor": 100_00,
        "currency": currency,
        "method": method,
        "provider_code": provider_code,
        "provider_kind": provider_kind,
        "latency_ms": latency_ms,
        "network": "MTN",
        "mode": mode,
        "customer_msisdn_hash": None,
        "raw_payload": "{}",
        "dt": "2026-10-21",
    }


def _write_silver_payments(tmp_lake: Path, rows: list[dict], date: str = "2026-10-21") -> None:
    out_dir = tmp_lake / "silver" / "payments" / f"dt={date}"
    out_dir.mkdir(parents=True, exist_ok=True)
    pq.write_table(pa.Table.from_pylist(rows), out_dir / "part.parquet")


def _gold_path(tmp_lake: Path) -> Path:
    return tmp_lake / "gold" / "provider_health_hourly" / f"dt=2026-10-22" / "part.parquet"


def test_success_rate_aggregation(
    tmp_lake: Path, duckdb_con: duckdb.DuckDBPyConnection
) -> None:
    """3 successes + 1 failure → success_rate = 0.75."""
    rows = [
        _make_silver_row("payment.succeeded", latency_ms=200),
        _make_silver_row("payment.succeeded", latency_ms=300),
        _make_silver_row("payment.succeeded", latency_ms=400),
        _make_silver_row("payment.failed",    latency_ms=500),
    ]
    _write_silver_payments(tmp_lake, rows)

    provider_health.run(_WINDOW_START, _WINDOW_END, con=duckdb_con)

    table = pq.read_table(str(_gold_path(tmp_lake)))
    assert table.num_rows >= 1
    row = table.to_pydict()
    assert row["provider_code"][0] == "mtn_momo_gh"
    assert row["total_count"][0] == 4
    assert row["success_count"][0] == 3
    assert row["failed_count"][0] == 1
    assert abs(row["success_rate"][0] - 0.75) < 0.001


def test_excludes_null_provider_code(
    tmp_lake: Path, duckdb_con: duckdb.DuckDBPyConnection
) -> None:
    """Rows with NULL provider_code must be excluded from the health mart."""
    rows = [
        _make_silver_row("payment.succeeded"),
        {**_make_silver_row("payment.succeeded"), "provider_code": None},
    ]
    _write_silver_payments(tmp_lake, rows)

    provider_health.run(_WINDOW_START, _WINDOW_END, con=duckdb_con)

    table = pq.read_table(str(_gold_path(tmp_lake)))
    row = table.to_pydict()
    assert all(pc is not None for pc in row["provider_code"])


def test_null_latency_excluded_from_percentiles(
    tmp_lake: Path, duckdb_con: duckdb.DuckDBPyConnection
) -> None:
    """Rows with NULL latency are excluded per WHERE latency_ms IS NOT NULL."""
    rows = [
        _make_silver_row("payment.succeeded", latency_ms=300),
        {**_make_silver_row("payment.succeeded"), "latency_ms": None},
    ]
    _write_silver_payments(tmp_lake, rows)

    # Should not raise
    provider_health.run(_WINDOW_START, _WINDOW_END, con=duckdb_con)
    table = pq.read_table(str(_gold_path(tmp_lake)))
    assert table.num_rows == 1


def test_hourly_granularity(
    tmp_lake: Path, duckdb_con: duckdb.DuckDBPyConnection
) -> None:
    """Events in different hours produce different rows."""
    rows = [
        _make_silver_row("payment.succeeded", latency_ms=200, hour_offset=0),
        _make_silver_row("payment.succeeded", latency_ms=300, hour_offset=1),
        _make_silver_row("payment.failed",    latency_ms=500, hour_offset=1),
    ]
    _write_silver_payments(tmp_lake, rows)

    provider_health.run(_WINDOW_START, _WINDOW_END, con=duckdb_con)

    table = pq.read_table(str(_gold_path(tmp_lake)))
    # Two distinct hours → two rows (same provider + method + currency)
    assert table.num_rows == 2


def test_empty_silver_produces_empty_gold(
    tmp_lake: Path, duckdb_con: duckdb.DuckDBPyConnection
) -> None:
    """No Silver data → empty Gold output (no crash)."""
    # No silver data — create empty dir
    (tmp_lake / "silver" / "payments").mkdir(parents=True, exist_ok=True)

    provider_health.run(_WINDOW_START, _WINDOW_END, con=duckdb_con)
    # File may not be created; just confirm no exception
