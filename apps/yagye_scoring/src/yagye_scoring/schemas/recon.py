"""Reconciliation break scoring request / response schemas."""

from typing import Literal

from pydantic import BaseModel, Field


class ReconBreakScoringRequest(BaseModel):
    break_id: str  # ReconciliationBreak.public_id ("brk_…")
    amount_delta_minor: int  # expected_amount - actual_amount (signed)
    expected_amount: int = Field(ge=0)
    age_hours: float = Field(ge=0.0)
    has_right_ref: bool  # True when provider reference is present on the break
    settlement_offset_days: int = 0


class ReconBreakScoringResponse(BaseModel):
    break_id: str
    classification: Literal[
        "timing_difference",
        "fee_discrepancy",
        "missing_on_right",
        "amount_mismatch",
    ]
    confidence: float = Field(ge=0.0, le=1.0)
    model_version: str
