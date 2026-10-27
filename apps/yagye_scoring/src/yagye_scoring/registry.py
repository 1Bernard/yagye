"""ModelRegistry — loads all ONNX models at service startup.

At P20, no trained ONNX files exist. The registry starts all models in
rule-based fallback mode (is_loaded=False) and logs the status. Post-P22,
ONNX files are uploaded to S3 under yagye-ml-models/ and the service
picks them up on next restart.

S3 layout expected:
  s3://yagye-ml-models/routing_native_rail/<champion-version>/model.onnx
  s3://yagye-ml-models/routing_external_psp/<champion-version>/model.onnx
  s3://yagye-ml-models/risk_scorer/<champion-version>/model.onnx
  s3://yagye-ml-models/reserve_recommender/<champion-version>/model.onnx
  s3://yagye-ml-models/churn_predictor/<champion-version>/model.onnx

Each model directory contains a champion.flag file whose content is the
version string (e.g. "v1.0.0"). The registry reads that flag to locate
the correct version directory.
"""

from __future__ import annotations

import os
import tempfile
from dataclasses import dataclass, field

import redis.asyncio as aioredis

from yagye_scoring.config import settings
from yagye_scoring.features.base import FeatureClient
from yagye_scoring.models.churn_predictor import ChurnPredictor
from yagye_scoring.models.reserve_recommender import ReserveRecommender
from yagye_scoring.models.risk_scorer import RiskScorer
from yagye_scoring.models.routing_predictor import RoutingPredictor, make_routing_models
from yagye_scoring.shared.logging import get_logger
from yagye_scoring.shared.s3_client import get_s3_client

logger = get_logger(__name__)


@dataclass
class ModelRegistry:
    routing_native_rail: RoutingPredictor
    routing_external_psp: RoutingPredictor
    risk_scorer: RiskScorer
    reserve_recommender: ReserveRecommender
    churn_predictor: ChurnPredictor
    feature_client: FeatureClient
    _redis: aioredis.Redis = field(repr=False)  # type: ignore[type-arg]

    def health_checks(self) -> dict[str, bool]:
        redis_ok = False
        try:
            # Synchronous ping in an async context — acceptable for readiness check
            import asyncio

            redis_ok = asyncio.get_event_loop().run_until_complete(
                self._redis.ping()  # type: ignore[attr-defined]
            )
        except Exception:
            pass
        return {
            "routing_native_rail": True,  # rule-based fallback always ready
            "routing_external_psp": True,
            "risk_scorer": True,
            "reserve_recommender": True,
            "churn_predictor": True,
            "redis": redis_ok,
        }

    @classmethod
    async def load(cls) -> ModelRegistry:
        redis = aioredis.from_url(settings.redis_url, decode_responses=True)
        feature_client = FeatureClient(redis)

        native, external = make_routing_models()
        risk = RiskScorer("risk_scorer")
        reserve = ReserveRecommender("reserve_recommender", settings.reserve_default_rate)
        churn = ChurnPredictor("churn_predictor")

        registry = cls(
            routing_native_rail=native,
            routing_external_psp=external,
            risk_scorer=risk,
            reserve_recommender=reserve,
            churn_predictor=churn,
            feature_client=feature_client,
            _redis=redis,
        )

        await registry._try_load_from_s3()
        registry._log_status()
        return registry

    async def _try_load_from_s3(self) -> None:
        """Attempt to load champion ONNX files from S3. Silently skip if absent."""
        models = [
            (self.routing_native_rail, "routing_native_rail"),
            (self.routing_external_psp, "routing_external_psp"),
            (self.risk_scorer, "risk_scorer"),
            (self.reserve_recommender, "reserve_recommender"),
            (self.churn_predictor, "churn_predictor"),
        ]
        s3 = get_s3_client()
        bucket = settings.ml_models_bucket

        for model, prefix in models:
            try:
                flag_key = f"{prefix}/champion.flag"
                response = s3.get_object(Bucket=bucket, Key=flag_key)
                version = response["Body"].read().decode().strip()

                model_key = f"{prefix}/{version}/model.onnx"
                with tempfile.NamedTemporaryFile(suffix=".onnx", delete=False) as tmp:
                    s3.download_fileobj(bucket, model_key, tmp)
                    tmp_path = tmp.name

                model.load_from_path(tmp_path)
                os.unlink(tmp_path)

            except Exception as exc:
                logger.info(
                    "model_s3_skip",
                    model=prefix,
                    reason=str(exc),
                    fallback="rule_based",
                )

    def _log_status(self) -> None:
        for model in [
            self.routing_native_rail,
            self.routing_external_psp,
            self.risk_scorer,
            self.reserve_recommender,
            self.churn_predictor,
        ]:
            logger.info(
                "model_status",
                model=model.model_name,
                loaded=model.is_loaded,
                version=model.version,
            )
