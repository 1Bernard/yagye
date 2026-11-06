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


def test_payments_mart_does_not_write_provider_health(
    tmp_lake: Path, duckdb_con: duckdb.DuckDBPyConnection
) -> None:
    """payments_mart must NOT write provider_health_hourly — that is provider_health.py's job."""
    rows = [_make_silver_row("payment.succeeded"), _make_silver_row("payment.failed")]
    _write_silver_payments(tmp_lake, rows)

    payments_mart.run(_WINDOW_START, _WINDOW_END, con=duckdb_con)

    assert not _provider_health_path(tmp_lake).exists(), (
        "payments_mart wrote to provider_health_hourly — "
        "this causes a schema collision with provider_health.py"
    )
