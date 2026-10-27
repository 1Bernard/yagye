"""Runtime configuration backed by environment variables."""

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        frozen=True,
        case_sensitive=False,
    )

    # ── Service ───────────────────────────────────────────────────────────────
    app_env: str = "development"
    port: int = 8000

    # ── S3 / Floci ────────────────────────────────────────────────────────────
    s3_endpoint_url: str | None = None
    s3_access_key_id: str = "test"
    s3_secret_access_key: str = "test"
    s3_region: str = "us-east-1"
    ml_models_bucket: str = "yagye-ml-models"

    # ── Redis (feature store) ─────────────────────────────────────────────────
    redis_url: str = "redis://localhost:6379/0"
    # Features older than this are treated as stale → static_fallback
    feature_staleness_seconds: int = 300

    # ── Scoring thresholds ────────────────────────────────────────────────────
    routing_score_threshold: float = 0.60
    risk_block_threshold: float = 0.70
    risk_review_threshold: float = 0.30
    reserve_default_rate: float = 0.05  # 5% fallback when model not loaded
    churn_alert_threshold: float = 0.65

    # ── ML rollout flags (0 = shadow only, 100 = fully active) ───────────────
    # These are env-var overrides for dev; production uses DB-backed config.
    routing_ml_rollout_percent: int = 0
    risk_ml_rollout_percent: int = 0

    @property
    def is_production(self) -> bool:
        return self.app_env == "production"

    @property
    def use_json_logging(self) -> bool:
        return self.app_env in ("production", "staging")


settings = Settings()
