# Floci Setup Guide

**Last updated:** 2026-10-18

Floci is the local AWS emulator used in development and CI to simulate S3 and
KMS without real AWS credentials. It runs as a Docker service on the `data`
network and is API-compatible with AWS S3.

---

## 1. Starting Floci

Floci runs as part of the dev Docker Compose stack. Confirm it is in
`docker-compose.yml` (or `docker-compose.dev.yml`) under the `data` network:

```yaml
services:
  floci:
    image: localstack/localstack:3.4
    ports:
      - "4566:4566"
    environment:
      - SERVICES=s3,kms
      - DEBUG=0
    networks:
      - data
```

Start it:

```bash
docker compose up -d floci
```

Verify it is healthy:

```bash
curl -s http://localhost:4566/_localstack/health | python3 -m json.tool
# Should show "s3": "running", "kms": "running"
```

---

## 2. Creating the Buckets

Use the AWS CLI with the Floci endpoint. The credentials are dummy values —
Floci accepts any non-empty key and secret:

```bash
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1

# Raw events bucket (append-only)
aws --endpoint-url http://localhost:4566 s3 mb s3://yagye-lake-raw

# Curated feature tables bucket (rewritten by ETL jobs)
aws --endpoint-url http://localhost:4566 s3 mb s3://yagye-lake-curated

# KYB documents bucket (deferred to P21, but create now for readiness)
aws --endpoint-url http://localhost:4566 s3 mb s3://yagye-kyb-documents

# Verify all three exist
aws --endpoint-url http://localhost:4566 s3 ls
```

Expected output:
```
2026-10-18 12:00:00 yagye-kyb-documents
2026-10-18 12:00:00 yagye-lake-curated
2026-10-18 12:00:00 yagye-lake-raw
```

---

## 3. Test: Write and Query a Parquet File with DuckDB

This verifies the full read/write path before running any ETL jobs.

Install DuckDB locally (if not present):

```bash
pip install duckdb pyarrow
```

Create a test Parquet file and upload it:

```python
# test_floci.py — run from any directory

import duckdb
import os

conn = duckdb.connect()

# Point DuckDB at Floci
conn.execute("""
  INSTALL httpfs;
  LOAD httpfs;
  SET s3_endpoint = 'localhost:4566';
  SET s3_access_key_id = 'test';
  SET s3_secret_access_key = 'test';
  SET s3_region = 'us-east-1';
  SET s3_url_style = 'path';
  SET s3_use_ssl = false;
""")

# Write a synthetic payment.succeeded event batch
conn.execute("""
  COPY (
    SELECT
      'pay_018e1234' AS public_id,
      'mch_001'      AS merchant_code,
      'mtn_momo_gh'  AS provider_code,
      'succeeded'    AS outcome,
      10000          AS amount_minor,
      'GHS'          AS currency,
      'live'         AS mode,
      TIMESTAMPTZ '2026-10-18 12:00:00' AS occurred_at
  )
  TO 's3://yagye-lake-raw/payment.succeeded/year=2026/month=10/day=18/test_batch.parquet'
  (FORMAT 'parquet')
""")

print("Write OK")

# Read it back
result = conn.execute("""
  SELECT
    merchant_code,
    provider_code,
    COUNT(*) AS attempts,
    SUM(amount_minor) AS total_volume
  FROM read_parquet(
    's3://yagye-lake-raw/payment.succeeded/year=2026/month=10/day=18/*.parquet'
  )
  GROUP BY merchant_code, provider_code
""").fetchall()

for row in result:
  print(row)
# Expected: ('mch_001', 'mtn_momo_gh', 1, 10000)

print("Read OK — Floci + DuckDB working")
```

Run it:

```bash
python3 test_floci.py
```

---

## 4. Production vs Local: What Changes

When deploying to production, the only change is the S3 endpoint configuration.
The DuckDB ETL jobs read the endpoint from an environment variable:

```python
endpoint = os.getenv("S3_ENDPOINT", "localhost:4566")
use_ssl   = os.getenv("S3_USE_SSL", "false") == "true"

conn.execute(f"""
  SET s3_endpoint = '{endpoint}';
  SET s3_use_ssl = {str(use_ssl).lower()};
""")
# In production: S3_ENDPOINT="" (empty = real AWS), S3_USE_SSL=true
```

Real AWS credentials are injected via IAM instance roles in production —
no `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` environment variables are
needed in production containers.

---

## 5. Troubleshooting

**"Connection refused" on port 4566:**
Floci is not running. Run `docker compose up -d floci` and wait ~5 seconds.

**"NoSuchBucket" from DuckDB:**
The buckets were not created. Run the `aws s3 mb` commands in §2.

**DuckDB `s3_url_style = 'path'` required:**
Floci does not support virtual-hosted-style S3 URLs (e.g.
`yagye-lake-raw.localhost:4566`). Always set `s3_url_style = 'path'` locally.
This setting is only needed for Floci — real AWS uses path-style by default
for non-default regions.

**Parquet file not visible after write:**
Check that the S3 path exactly matches the `read_parquet` glob. DuckDB's
`**/*.parquet` glob matches any depth, but a typo in the bucket name or
partition prefix will silently return 0 rows.
