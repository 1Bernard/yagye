"""Risk scoring request / response schemas."""

from typing import Literal

from pydantic import BaseModel, Field


class RiskScoringRequest(BaseModel):
    payment_id: str
    merchant_id: str
    customer_msisdn_hash: str  # SHA-256 of the raw MSISDN, never the raw value
    amount_minor: int = Field(ge=0)
    hour_of_day: int = Field(ge=0, le=23)
    day_of_week: int = Field(ge=0, le=6)
    customer_kyc_tier: int = Field(ge=1, le=3)
    is_new_customer: bool = False
    is_new_msisdn_for_merchant: bool = False


class RiskScoringResponse(BaseModel):
    payment_id: str
    risk_score: float = Field(ge=0.0, le=1.0)
    # decision mirrors the configured thresholds — Core enforces the action
    decision: Literal["allow", "review", "block"]
    model_version: str
    feature_source: Literal["realtime", "degraded_cache", "static_fallback"]
