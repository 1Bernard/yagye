"""Shared pytest fixtures.

Tests use a local temporary directory for Parquet files instead of real S3.
DuckDB reads from local paths the same way it reads from s3:// URIs, so no
mocking of S3 is needed — we just point the config at file:// paths.

The `monkeypatch` approach keeps each test hermetically isolated.
"""

import os
import tempfile
from collections.abc import Generator
from pathlib import Path

import pytest


@pytest.fixture
def tmp_lake(tmp_path: Path) -> Path:
    """A temporary directory tree that mimics the three-bucket layout."""
    for bucket in ("raw", "silver", "gold", "models"):
        (tmp_path / bucket).mkdir()
    return tmp_path


@pytest.fixture(autouse=True)
def patch_settings(monkeypatch: pytest.MonkeyPatch, tmp_lake: Path) -> None:
    """Point all bucket settings at the local tmp directory for tests."""
    monkeypatch.setenv("S3_ENDPOINT_URL", "")
    monkeypatch.setenv("BRONZE_BUCKET", str(tmp_lake / "raw"))
    monkeypatch.setenv("SILVER_BUCKET", str(tmp_lake / "silver"))
    monkeypatch.setenv("GOLD_BUCKET", str(tmp_lake / "gold"))
    monkeypatch.setenv("ML_MODELS_BUCKET", str(tmp_lake / "models"))
    monkeypatch.setenv("ANTHROPIC_API_KEY", "test-key")
    monkeypatch.setenv("DATABASE_URL", "postgresql://localhost/test")


@pytest.fixture
def duckdb_con():
    """A plain in-memory DuckDB connection (no S3 config needed for local tests)."""
    import duckdb

    con = duckdb.connect()
    con.execute("INSTALL parquet; LOAD parquet;")
    yield con
    con.close()
