"""S3 / Floci client factory.

All bucket access goes through this module so that Floci (local emulator) vs
real AWS is a single config switch (s3_endpoint_url).
"""

from __future__ import annotations

from typing import TYPE_CHECKING, Any

import boto3

from yagye_data.config import settings

if TYPE_CHECKING:
    from mypy_boto3_s3 import S3Client


def get_s3_client() -> S3Client:
    kwargs: dict[str, Any] = {
        "region_name": settings.s3_region,
        "aws_access_key_id": settings.s3_access_key_id,
        "aws_secret_access_key": settings.s3_secret_access_key,
    }
    if settings.s3_endpoint_url:
        kwargs["endpoint_url"] = settings.s3_endpoint_url

    return boto3.client("s3", **kwargs)


def ensure_bucket(bucket: str) -> None:
    """Create the bucket if it doesn't exist (idempotent, Floci-safe)."""
    client = get_s3_client()
    try:
        client.head_bucket(Bucket=bucket)
    except client.exceptions.ClientError:
        if settings.s3_endpoint_url:
            # Floci / LocalStack uses path-style; skip LocationConstraint
            client.create_bucket(Bucket=bucket)
        else:
            client.create_bucket(
                Bucket=bucket,
                CreateBucketConfiguration={"LocationConstraint": settings.s3_region},
            )


def s3_uri(bucket: str, key: str) -> str:
    # Local paths (used in tests via monkeypatched bucket env vars) bypass s3://
    if bucket.startswith("/"):
        return f"{bucket}/{key}"
    return f"s3://{bucket}/{key}"
