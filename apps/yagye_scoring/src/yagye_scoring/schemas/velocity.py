"""Velocity scoring request / response schemas."""

from pydantic import BaseModel, Field


class VelocityScoringRequest(BaseModel):
    payment_id: str
    msisdn_hash: str  # SHA-256 of the raw MSISDN — never the raw value
    merchant_id: str
    amount_minor: int = Field(ge=0)
    payment_method: str  # "mobile_money" | "card"
    hour_of_day: int = Field(ge=0, le=23)
    day_of_week: int = Field(ge=0, le=6)


class VelocityScoringResponse(BaseModel):
    payment_id: str
    anomaly_score: float = Field(ge=0.0, le=1.0)
    is_anomaly: bool
    model_version: str
    feature_source: str
