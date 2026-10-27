"""Reserve recommendation request / response schemas."""

from pydantic import BaseModel, Field


class ReserveScoringRequest(BaseModel):
    merchant_id: str


class ReserveScoringResponse(BaseModel):
    merchant_id: str
    recommended_rate: float = Field(ge=0.0, le=1.0)  # e.g. 0.035 = 3.5%
    recommended_duration_days: int
    model_version: str
    feature_source: str
