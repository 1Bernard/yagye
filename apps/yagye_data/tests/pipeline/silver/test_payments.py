"""Unit tests for Silver payments ETL.

Tests write Bronze NDJSON into the tmp_lake fixture and call payments.run()
directly so the pipeline code is exercised and counted in coverage.
"""

import json
import uuid
from datetime import UTC, datetime, timedelta
from pathlib import Path

import duckdb
import pyarrow.parquet as pq
import pytest

from yagye_data.pipeline.silver import payments as silver_payments

_WINDOW_START = datetime(2026, 10, 21, 0, 0, 0, tzinfo=UTC)
_WINDOW_END = datetime(2026, 10, 22, 0, 0, 0, tzinfo=UTC)


def _make_envelope(
    event_type: str = "payment.succeeded",
    event_id: str | None = None,
    occurred_at: datetime | None = None,
    provider_code: str = "mtn_momo_gh",
    latency_ms: int = 320,
    mode: str = "simulation",
    customer_msisdn: str | None = "0241000001",
) -> dict:
    ts = occurred_at or datetime(2026, 10, 21, 10, 0, 0, tzinfo=UTC)
    payload: dict = {
        "amount": 10_00,
        "currency": "GHS",
        "method": "mobile_money",
        "provider_code": provider_code,
        "latency_ms": latency_ms,
        "network": "MTN",
    }
    if customer_msisdn:
        payload["customer_msisdn"] = customer_msisdn
    return {
        "event_id": event_id or str(uuid.uuid4()),
        "event_type": event_type,
        "merchant_id": str(uuid.uuid4()),
        "aggregate_id": str(uuid.uuid4()),
        "occurred_at": ts.isoformat(),
        "mode": mode,
        "correlation_id": str(uuid.uuid4()),
        "payload": json.dumps(payload),
    }


def _write_bronze_ndjson(tmp_lake: Path, rows: list[dict], date: str = "2026-10-21") -> Path:
    out_dir = tmp_lake / "raw" / "events" / f"dt={date}"
    out_dir.mkdir(parents=True, exist_ok=True)
    path = out_dir / "payment_test.ndjson"
    with path.open("w") as f:
        for row in rows:
            f.write(json.dumps(row) + "\n")
    return path


def _silver_path(tmp_lake: Path, date: str = "2026-10-21") -> Path:
    return tmp_lake / "silver" / "payments" / f"dt={date}" / "part.parquet"


def test_payments_silver_deduplicates(
    tmp_lake: Path, duckdb_con: duckdb.DuckDBPyConnection
) -> None:
    """Duplicate event_ids must produce only one output row."""
    shared_id = str(uuid.uuid4())
    ts = datetime(2026, 10, 21, 10, 0, 0, tzinfo=UTC)
    rows = [
        _make_envelope(event_id=shared_id, occurred_at=ts),
        _make_envelope(event_id=shared_id, occurred_at=ts + timedelta(seconds=1)),
        _make_envelope(),  # distinct id — should also appear
    ]
    _write_bronze_ndjson(tmp_lake, rows)

    silver_payments.run(_WINDOW_START, _WINDOW_END, con=duckdb_con)

    table = pq.read_table(str(_silver_path(tmp_lake)))
    assert table.num_rows == 2, f"Expected 2 unique events, got {table.num_rows}"


def test_payments_silver_filters_event_types(
    tmp_lake: Path, duckdb_con: duckdb.DuckDBPyConnection
) -> None:
    """Only payment.succeeded / failed / indeterminate events should pass through."""
    rows = [
        _make_envelope(event_type="payment.succeeded"),
        _make_envelope(event_type="payment.failed"),
        _make_envelope(event_type="merchant.registered"),
        _make_envelope(event_type="settlement_batch.created"),
    ]
    _write_bronze_ndjson(tmp_lake, rows)

    silver_payments.run(_WINDOW_START, _WINDOW_END, con=duckdb_con)

    table = pq.read_table(str(_silver_path(tmp_lake)))
    assert table.num_rows == 2


def test_payments_silver_extracts_mode_and_msisdn_hash(
    tmp_lake: Path, duckdb_con: duckdb.DuckDBPyConnection
) -> None:
    """mode column must be preserved; customer_msisdn must be SHA-256 hashed."""
    rows = [_make_envelope(mode="live", customer_msisdn="0241000001")]
    _write_bronze_ndjson(tmp_lake, rows)

    silver_payments.run(_WINDOW_START, _WINDOW_END, con=duckdb_con)

    table = pq.read_table(str(_silver_path(tmp_lake)))
    row = table.to_pydict()
    assert row["mode"][0] == "live"
    assert row["customer_msisdn_hash"][0] is not None
    assert len(row["customer_msisdn_hash"][0]) == 64  # SHA-256 hex digest


@pytest.mark.integration
def test_payments_silver_null_msisdn_hash(
    tmp_lake: Path, duckdb_con: duckdb.DuckDBPyConnection
) -> None:
    """Payments without customer_msisdn must produce NULL for the hash column."""
    rows = [_make_envelope(customer_msisdn=None)]
    _write_bronze_ndjson(tmp_lake, rows)

    silver_payments.run(_WINDOW_START, _WINDOW_END, con=duckdb_con)

    table = pq.read_table(str(_silver_path(tmp_lake)))
    row = table.to_pydict()
    assert row["customer_msisdn_hash"][0] is None
