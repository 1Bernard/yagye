"""POST /score/velocity — velocity & burst anomaly scorer endpoint."""

from fastapi import APIRouter

from yagye_scoring.dependencies import Registry
from yagye_scoring.features.customer_risk import get_customer_features
from yagye_scoring.models.velocity_scorer import ANOMALY_THRESHOLD
from yagye_scoring.schemas.velocity import VelocityScoringRequest, VelocityScoringResponse
from yagye_scoring.shared.logging import get_logger

router = APIRouter(tags=["scoring"])
logger = get_logger(__name__)


@router.post("/score/velocity", response_model=VelocityScoringResponse)
async def score_velocity(
    req: VelocityScoringRequest, registry: Registry
) -> VelocityScoringResponse:
    customer_features, feature_source = await get_customer_features(
        req.msisdn_hash, registry.feature_client
    )

    features = {
        **customer_features,
        "amount_minor": float(req.amount_minor),
        "is_momo": 1.0 if req.payment_method == "mobile_money" else 0.0,
        "hour_of_day": float(req.hour_of_day),
        "day_of_week": float(req.day_of_week),
    }

    score = registry.velocity_scorer.predict(features)
    is_anomaly = score >= ANOMALY_THRESHOLD

    logger.info(
        "velocity.scored",
        payment_id=req.payment_id,
        anomaly_score=score,
        is_anomaly=is_anomaly,
        model_version=registry.velocity_scorer.version,
        feature_source=feature_source,
    )

    return VelocityScoringResponse(
        payment_id=req.payment_id,
        anomaly_score=score,
        is_anomaly=is_anomaly,
        model_version=registry.velocity_scorer.version,
        feature_source=feature_source,
    )
