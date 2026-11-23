"""POST /score/recon_break — reconciliation break classifier endpoint."""

from fastapi import APIRouter

from yagye_scoring.dependencies import Registry
from yagye_scoring.schemas.recon import ReconBreakScoringRequest, ReconBreakScoringResponse
from yagye_scoring.shared.logging import get_logger

router = APIRouter(tags=["scoring"])
logger = get_logger(__name__)


@router.post("/score/recon_break", response_model=ReconBreakScoringResponse)
async def score_recon_break(
    req: ReconBreakScoringRequest, registry: Registry
) -> ReconBreakScoringResponse:
    abs_delta = abs(req.amount_delta_minor)
    relative_delta = (abs_delta / req.expected_amount) if req.expected_amount > 0 else 0.0

    features = {
        "amount_delta_minor": float(req.amount_delta_minor),
        "abs_delta_minor": float(abs_delta),
        "relative_delta": min(relative_delta, 1.0),
        "age_hours": float(req.age_hours),
        "has_right_ref": 1.0 if req.has_right_ref else 0.0,
        "settlement_offset_days": float(req.settlement_offset_days),
    }

    classification, confidence = registry.recon_break_classifier.classify_break(features)

    logger.info(
        "recon_break.classified",
        break_id=req.break_id,
        classification=classification,
        confidence=round(confidence, 4),
        model_version=registry.recon_break_classifier.version,
    )

    return ReconBreakScoringResponse(
        break_id=req.break_id,
        classification=classification,
        confidence=confidence,
        model_version=registry.recon_break_classifier.version,
    )
