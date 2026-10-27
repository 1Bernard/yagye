"""POST /score/risk — risk scorer endpoint."""

from fastapi import APIRouter

from yagye_scoring.config import settings
from yagye_scoring.dependencies import Registry
from yagye_scoring.features.customer_risk import get_customer_features
from yagye_scoring.features.merchant_risk import get_merchant_features
from yagye_scoring.schemas.risk import RiskScoringRequest, RiskScoringResponse
from yagye_scoring.shared.logging import get_logger

router = APIRouter(tags=["scoring"])
logger = get_logger(__name__)


@router.post("/score/risk", response_model=RiskScoringResponse)
async def score_risk(req: RiskScoringRequest, registry: Registry) -> RiskScoringResponse:
    customer_features, customer_source = await get_customer_features(
        req.customer_msisdn_hash, registry.feature_client
    )
    merchant_features, merchant_source = await get_merchant_features(
        req.merchant_id, registry.feature_client
    )

    # Worst source determines the response label
    sources = [customer_source, merchant_source]
    if "static_fallback" in sources:
        feature_source = "static_fallback"
    elif "degraded_cache" in sources:
        feature_source = "degraded_cache"
    else:
        feature_source = "realtime"

    features = {
        **customer_features,
        **merchant_features,
        "amount_minor": float(req.amount_minor),
        "amount_z_score": _compute_amount_z_score(req.amount_minor, merchant_features),
        "customer_kyc_tier_enc": float(req.customer_kyc_tier - 1),  # 0-indexed
        "hour_of_day": float(req.hour_of_day),
        "day_of_week": float(req.day_of_week),
        "is_new_customer": 1.0 if req.is_new_customer else 0.0,
        "is_new_msisdn_for_merchant": 1.0 if req.is_new_msisdn_for_merchant else 0.0,
    }

    score = registry.risk_scorer.predict(features)

    if score >= settings.risk_block_threshold:
        decision = "block"
    elif score >= settings.risk_review_threshold:
        decision = "review"
    else:
        decision = "allow"

    logger.info(
        "risk.scored",
        payment_id=req.payment_id,
        risk_score=score,
        decision=decision,
        model_version=registry.risk_scorer.version,
        feature_source=feature_source,
    )

    return RiskScoringResponse(
        payment_id=req.payment_id,
        risk_score=score,
        decision=decision,
        model_version=registry.risk_scorer.version,
        feature_source=feature_source,
    )


def _compute_amount_z_score(amount: int, merchant_features: dict) -> float:
    avg = merchant_features.get("avg_payment_amount", 0.0)
    std = merchant_features.get("payment_amount_std", 1.0)
    if std == 0.0:
        return 0.0
    return (float(amount) - avg) / std
