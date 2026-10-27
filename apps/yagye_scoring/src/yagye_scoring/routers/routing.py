"""POST /score/routing — routing health predictor endpoint.

Core calls this after resolving eligible providers (MSISDN constraint +
merchant entitlements applied). The scoring service only scores the candidates
it receives — it never makes cross-network substitutions.
"""

from fastapi import APIRouter

from yagye_scoring.config import settings
from yagye_scoring.dependencies import Registry
from yagye_scoring.features.provider_health import get_provider_features
from yagye_scoring.schemas.routing import (
    ProviderScore,
    RoutingScoringRequest,
    RoutingScoringResponse,
)
from yagye_scoring.shared.logging import get_logger

router = APIRouter(tags=["scoring"])
logger = get_logger(__name__)


@router.post("/score/routing", response_model=RoutingScoringResponse)
async def score_routing(req: RoutingScoringRequest, registry: Registry) -> RoutingScoringResponse:
    provider_codes = [c.provider_code for c in req.provider_candidates]

    raw_features, feature_source = await get_provider_features(
        provider_codes, registry.feature_client
    )

    # Select model instance based on provider_kind of the candidates.
    # Mixed-kind lists (rare: card PSPs + MoMo aggregators on same payment) use
    # external_psp model — it was trained on multi-candidate selection.
    kinds = {c.provider_kind for c in req.provider_candidates}
    model = (
        registry.routing_external_psp
        if "external_psp" in kinds
        else registry.routing_native_rail
    )

    scores: list[ProviderScore] = []
    for candidate in req.provider_candidates:
        provider_features = raw_features.get(candidate.provider_code, {})
        features = {
            **provider_features,
            "amount_bucket": req.amount_minor // 10_000,
            "hour_of_day": req.hour_of_day,
            "day_of_week": req.day_of_week,
            "candidate_count": len(req.provider_candidates),
        }
        score = model.predict(features)
        scores.append(
            ProviderScore(
                provider_code=candidate.provider_code,
                provider_kind=candidate.provider_kind,
                score=score,
            )
        )

    sorted_scores = sorted(scores, key=lambda s: s.score, reverse=True)
    threshold = settings.routing_score_threshold

    if all(s.score < threshold for s in sorted_scores):
        routing_mode = "hold_all"
    elif len(sorted_scores) == 1:
        routing_mode = "go_hold"
    else:
        routing_mode = "provider_selection"

    logger.info(
        "routing.scored",
        payment_id=req.payment_id,
        routing_mode=routing_mode,
        top_provider=sorted_scores[0].provider_code if sorted_scores else None,
        top_score=sorted_scores[0].score if sorted_scores else None,
        model=model.model_name,
        model_version=model.version,
        feature_source=feature_source,
        candidate_count=len(req.provider_candidates),
    )

    return RoutingScoringResponse(
        payment_id=req.payment_id,
        provider_scores=sorted_scores,
        routing_mode=routing_mode,
        model_version=model.version,
        feature_source=feature_source,
    )
