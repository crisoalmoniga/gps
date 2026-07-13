from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field


class ReportCreate(BaseModel):
    lat: float = Field(..., ge=-90, le=90)
    lon: float = Field(..., ge=-180, le=180)
    is_retroactive: bool = False
    occurred_at: Optional[datetime] = None


class ReportDetailUpdate(BaseModel):
    incident_type: Optional[str] = None
    severity: Optional[str] = None
    description: Optional[str] = None
    occurred_at: Optional[datetime] = None


class ReportOut(BaseModel):
    id: int
    lat: float
    lon: float
    incident_type: Optional[str]
    severity: Optional[str]
    description: Optional[str]
    is_retroactive: bool
    occurred_at: Optional[datetime]
    created_at: datetime

    class Config:
        from_attributes = True


class RoutePoint(BaseModel):
    lat: float
    lon: float


class RouteOut(BaseModel):
    distance_meters: float
    duration_seconds: float
    geometry: list[list[float]]  # [[lon, lat], ...]
    avg_risk_score: float = 0.0
    avg_congestion_pct: float = 0.0


class TripPointIn(BaseModel):
    lat: float = Field(..., ge=-90, le=90)
    lon: float = Field(..., ge=-180, le=180)
    speed_kmh: float = Field(..., ge=0)
    recorded_at: datetime


class TripUpload(BaseModel):
    trip_id: str
    points: list[TripPointIn]


class RiskZoneOut(BaseModel):
    id: int
    lat: float
    lon: float
    hour_bucket: int
    score: float
    confidence: float
    category: Optional[str]
    incident_count: int

    class Config:
        from_attributes = True


class MentionIn(BaseModel):
    source_account: str
    external_id: str
    raw_text: str
    posted_at: Optional[datetime] = None
