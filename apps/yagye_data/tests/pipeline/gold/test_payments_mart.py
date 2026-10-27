"""Unit tests for Gold payments mart.

Tests write Silver Parquet into the tmp_lake fixture and call
payments_mart.run() directly so the pipeline code is counted in coverage.
"""

import uuid
from datetime import UTC, datetime, timedelta
from pathlib import Path

import duckdb
import pyarrow as pa
import pyarrow.parquet as pq

from yagye_data.pipeline.gold import payments_mart

_WINDOW_START = datetime(2026, 10, 21, 0, 0, 0, tzinfo=UTC)
_WINDOW_END = datetime(2026, 10, 22, 0, 0, 0, tzinfo=UTC)


def _make_silver_row(
    event_type: str = "payment.succeeded",
    provider_code: str = "mtn_momo_gh",
    latency_ms: int = 300,
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
        "currency": "GHS",
        "method": "mobile_money",
        "provider_code": provider_code,
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


def _provider_health_path(tmp_lake: Path, date: str = "2026-10-21") -> Path:
    return tmp_lake / "gold" / "provider_health_hourly" / f"dt={date}" / "part.parquet"


def test_provider_health_success_rate(
    tmp_lake: Path, duckdb_con: duckdb.DuckDBPyConnection
) -> None:
    """3 successes + 1 failure → success_rate = 0.75; p50 of [200,300,400,500] = 350."""
    rows = [
        _make_silver_row("payment.succeeded", latency_ms=200),
        _make_silver_row("payment.succeeded", latency_ms=300),
        _make_silver_row("payment.succeeded", latency_ms=400),
        _make_silver_row("payment.failed",    latency_ms=500),
    ]
    _write_silver_payments(tmp_lake, rows)

    payments_mart.run(_WINDOW_START, _WINDOW_END, con=duckdb_con)

    table = pq.read_table(str(_provider_health_path(tmp_lake)))
    assert table.num_rows == 1
    row = table.to_pydict()
    assert row["provider_code"][0] == "mtn_momo_gh"
    assert row["attempt_count"][0] == 4
    assert abs(row["success_rate"][0] - 0.75) < 0.001
    assert abs(row["p50_latency_ms"][0] - 350.0) < 0.001


def test_provider_health_excludes_null_provider(
    tmp_lake: Path, duckdb_con: duckdb.DuckDBPyConnection
) -> None:
    """Rows with NULL provider_code must be excluded from the health mart."""
    rows = [
        _make_silver_row("payment.succeeded"),
        {**_make_silver_row("payment.succeeded"), "provider_code": None},
    ]
    _write_silver_payments(tmp_lake, rows)

    payments_mart.run(_WINDOW_START, _WINDOW_END, con=duckdb_con)

    table = pq.read_table(str(_provider_health_path(tmp_lake)))
    assert table.num_rows == 1


def test_provider_health_excludes_simulation(
    tmp_lake: Path, duckdb_con: duckdb.DuckDBPyConnection
) -> None:
    """Simulation-mode payments must be excluded from Gold analytics."""
    rows = [
        _make_silver_row("payment.succeeded", mode="live"),
        _make_silver_row("payment.succeeded", mode="simulation"),
    ]
    _write_silver_payments(tmp_lake, rows)

    payments_mart.run(_WINDOW_START, _WINDOW_END, con=duckdb_con)

    table = pq.read_table(str(_provider_health_path(tmp_lake)))
    row = table.to_pydict()
    assert row["attempt_count"][0] == 1
