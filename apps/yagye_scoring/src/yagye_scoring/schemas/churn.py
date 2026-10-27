"""Churn prediction request / response schemas."""

from pydantic import BaseModel, Field


class ChurnScoringRequest(BaseModel):
    merchant_id: str


class ChurnScoringResponse(BaseModel):
    merchant_id: str
    churn_score: float = Field(ge=0.0, le=1.0)  # P(churn within 30 days)
    at_risk: bool  # score > churn_alert_threshold
    model_version: str
    feature_source: str
