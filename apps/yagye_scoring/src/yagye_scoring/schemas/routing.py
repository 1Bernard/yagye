"""Routing scoring request / response schemas.

Core calls this endpoint after applying:
  1. MSISDN network constraint (MTN MSISDN → only MTN MoMo candidates)
  2. Merchant entitlement filters (only providers the merchant has active connections for)

The scoring service only scores what it is given — it never makes cross-network
substitutions.
"""

from typing import Literal

from pydantic import BaseModel, Field


class ProviderCandidate(BaseModel):
    provider_code: str
    provider_kind: Literal["native_rail", "external_psp"]


class RoutingScoringRequest(BaseModel):
    payment_id: str
    # Pre-filtered by Core: MSISDN constraint + merchant entitlements already applied.
    # 1 candidate → go/hold signal (Model A). N candidates → provider selection (Model B).
    provider_candidates: list[ProviderCandidate] = Field(min_length=1)
    payment_method: Literal["mobile_money", "card", "bank_transfer"]
    network_code: str | None = None  # MTN/Telecel/AirtelTigo for MoMo; null for card/bank
    amount_minor: int = Field(ge=0)
    hour_of_day: int = Field(ge=0, le=23)
    day_of_week: int = Field(ge=0, le=6)  # ISO weekday (0=Mon)


class ProviderScore(BaseModel):
    provider_code: str
    provider_kind: str
    score: float = Field(ge=0.0, le=1.0)  # P(success)


class RoutingScoringResponse(BaseModel):
    payment_id: str
    # Sorted descending by score. Pick provider_scores[0] for provider selection.
    provider_scores: list[ProviderScore]
    routing_mode: Literal["provider_selection", "go_hold", "hold_all"]
    # provider_selection: multiple candidates, pick highest above threshold
    # go_hold:           single candidate, score is a dispatch signal
    # hold_all:          all candidates below threshold, queue for retry
    model_version: str
    feature_source: Literal["realtime", "degraded_cache", "static_fallback"]
