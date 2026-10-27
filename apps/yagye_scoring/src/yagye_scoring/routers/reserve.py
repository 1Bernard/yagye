"""POST /score/reserve — reserve rate recommender endpoint.

The recommendation is advisory only. The ops team reviews it in the portal
before applying any reserve change.
"""

from fastapi import APIRouter

from yagye_scoring.dependencies import Registry
from yagye_scoring.features.merchant_risk import get_merchant_features
from yagye_scoring.schemas.reserve import ReserveScoringRequest, ReserveScoringResponse
from yagye_scoring.shared.logging import get_logger

router = APIRouter(tags=["scoring"])
logger = get_logger(__name__)


@router.post("/score/reserve", response_model=ReserveScoringResponse)
async def score_reserve(req: ReserveScoringRequest, registry: Registry) -> ReserveScoringResponse:
    features, feature_source = await get_merchant_features(req.merchant_id, registry.feature_client)

    rate, duration_days = registry.reserve_recommender.predict_reserve(features)

    logger.info(
        "reserve.scored",
        merchant_id=req.merchant_id,
        recommended_rate=rate,
        model_version=registry.reserve_recommender.version,
        feature_source=feature_source,
    )

    return ReserveScoringResponse(
        merchant_id=req.merchant_id,
        recommended_rate=rate,
        recommended_duration_days=duration_days,
        model_version=registry.reserve_recommender.version,
        feature_source=feature_source,
    )
