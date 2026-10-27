"""Shared pytest fixtures.

Tests use a local temporary directory for Parquet files instead of real S3.
DuckDB reads from local paths the same way it reads from s3:// URIs when the
bucket starts with '/' — see shared/s3_client.py.

The settings singleton is frozen (pydantic frozen=True), so env-var patches
have no effect after instantiation. We patch the module-level `settings`
binding in each pipeline module directly using monkeypatch.setattr().
"""

from collections.abc import Generator
from pathlib import Path

import duckdb
import pytest


@pytest.fixture
def tmp_lake(tmp_path: Path) -> Path:
    """A temporary directory tree that mimics the three-bucket layout."""
    for bucket in ("raw", "silver", "gold", "models"):
        (tmp_path / bucket).mkdir()
    return tmp_path


@pytest.fixture(autouse=True)
def patch_settings(monkeypatch: pytest.MonkeyPatch, tmp_lake: Path) -> None:
    """Replace the settings singleton with test-local bucket paths.

    Because Settings is frozen we cannot mutate the existing instance.
    Instead we create a fresh one with local paths and replace the module-level
    `settings` name in every pipeline module that reads bucket config.
    """
    import yagye_data.config as config_mod
    import yagye_data.pipeline.gold.payments_mart as gold_mart_mod
    import yagye_data.pipeline.silver.payments as silver_payments_mod

    test_settings = config_mod.Settings(
        bronze_bucket=str(tmp_lake / "raw"),
        silver_bucket=str(tmp_lake / "silver"),
        gold_bucket=str(tmp_lake / "gold"),
        ml_models_bucket=str(tmp_lake / "models"),
        s3_endpoint_url=None,
        anthropic_api_key="test-key",
    )
    monkeypatch.setattr(config_mod, "settings", test_settings)
    monkeypatch.setattr(silver_payments_mod, "settings", test_settings)
    monkeypatch.setattr(gold_mart_mod, "settings", test_settings)


@pytest.fixture
def duckdb_con() -> Generator[duckdb.DuckDBPyConnection, None, None]:
    """A plain in-memory DuckDB connection (no S3 config needed for local tests)."""
    con = duckdb.connect()
    con.execute("INSTALL parquet; LOAD parquet;")
    con.execute("INSTALL json; LOAD json;")
    yield con
    con.close()
