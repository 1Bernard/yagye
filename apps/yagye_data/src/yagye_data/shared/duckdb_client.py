"""DuckDB connection factory.

DuckDB connections are NOT thread-safe — each thread/process must create its
own connection. This module provides a factory rather than a singleton.

For S3 reads/writes DuckDB uses its httpfs extension, which is configured here
to point at Floci when s3_endpoint_url is set, or real AWS otherwise.
"""

import duckdb

from yagye_data.config import settings


def get_connection() -> duckdb.DuckDBPyConnection:
    """Return a new in-memory DuckDB connection pre-configured for S3/Floci."""
    con = duckdb.connect()
    con.execute("INSTALL httpfs; LOAD httpfs;")
    con.execute("INSTALL parquet; LOAD parquet;")

    if settings.s3_endpoint_url:
        # Strip http(s):// prefix — DuckDB wants the host:port form
        endpoint = settings.s3_endpoint_url.removeprefix("https://").removeprefix("http://")
        con.execute(f"""
            SET s3_endpoint        = '{endpoint}';
            SET s3_access_key_id   = '{settings.s3_access_key_id}';
            SET s3_secret_access_key = '{settings.s3_secret_access_key}';
            SET s3_region          = '{settings.s3_region}';
            SET s3_url_style       = 'path';
            SET s3_use_ssl         = false;
        """)
    else:
        # Real AWS — rely on instance profile or env credentials
        con.execute(f"SET s3_region = '{settings.s3_region}';")

    return con


def read_parquet(con: duckdb.DuckDBPyConnection, s3_glob: str) -> duckdb.DuckDBPyRelation:
    """Read Parquet file(s) via a glob path, e.g. s3://bucket/prefix/*.parquet."""
    return con.read_parquet(s3_glob)
