"""Runtime configuration backed by environment variables."""

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        frozen=True,
        case_sensitive=False,
    )

    # ── S3 / Floci ────────────────────────────────────────────────────────────
    # None → real AWS (credentials from env / instance profile)
    # Set to e.g. "http://localhost:4566" for Floci / LocalStack
    s3_endpoint_url: str | None = None
    s3_access_key_id: str = "test"
    s3_secret_access_key: str = "test"
    s3_region: str = "us-east-1"

    bronze_bucket: str = "yagye-lake-raw"
    silver_bucket: str = "yagye-lake-silver"
    gold_bucket: str = "yagye-lake-gold"
    ml_models_bucket: str = "yagye-ml-models"

    # ── Database (pre-P14 outbox polling) ─────────────────────────────────────
    database_url: str = "postgresql://postgres:postgres@localhost:5432/yagye_core_dev"

    # ── Anthropic ─────────────────────────────────────────────────────────────
    anthropic_api_key: str = ""

    # ── ETL tuning ────────────────────────────────────────────────────────────
    # Silver runs look back slightly further than their cadence to avoid missing
    # late-arriving Bronze files at partition boundaries.
    silver_etl_lookback_hours: int = 2
    # Gold runs look back 25h (not 24h) so the nightly window covers any DST edge.
    gold_etl_lookback_hours: int = 25

    # ── Observability ─────────────────────────────────────────────────────────
    app_env: str = "development"

    @property
    def is_production(self) -> bool:
        return self.app_env == "production"

    @property
    def use_json_logging(self) -> bool:
        return self.app_env in ("production", "staging")


settings = Settings()
