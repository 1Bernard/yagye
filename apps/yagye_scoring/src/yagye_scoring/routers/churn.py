"""POST /score/churn — merchant churn predictor endpoint."""

from fastapi import APIRouter

from yagye_scoring.config import settings
from yagye_scoring.dependencies import Registry
from yagye_scoring.features.merchant_risk import get_merchant_features
from yagye_scoring.schemas.churn import ChurnScoringRequest, ChurnScoringResponse
from yagye_scoring.shared.logging import get_logger

router = APIRouter(tags=["scoring"])
logger = get_logger(__name__)


@router.post("/score/churn", response_model=ChurnScoringResponse)
async def score_churn(req: ChurnScoringRequest, registry: Registry) -> ChurnScoringResponse:
    features, feature_source = await get_merchant_features(req.merchant_id, registry.feature_client)

    score = registry.churn_predictor.predict(features)
    at_risk = score > settings.churn_alert_threshold

    logger.info(
        "churn.scored",
        merchant_id=req.merchant_id,
        churn_score=score,
        at_risk=at_risk,
        model_version=registry.churn_predictor.version,
        feature_source=feature_source,
    )

    return ChurnScoringResponse(
        merchant_id=req.merchant_id,
        churn_score=score,
        at_risk=at_risk,
        model_version=registry.churn_predictor.version,
        feature_source=feature_source,
    )
