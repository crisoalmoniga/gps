from typing import Optional

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from ..database import get_db
from ..models import RiskZone
from ..schemas import RiskZoneOut
from ..timezone_utils import amba_now

router = APIRouter(prefix="/risk-zones", tags=["risk-zones"])


@router.get("", response_model=list[RiskZoneOut])
def list_risk_zones(
    hour: Optional[int] = Query(None, ge=0, le=23, description="Si se omite, usa la hora actual en AMBA"),
    db: Session = Depends(get_db),
):
    """Zonas de riesgo agregadas por la Capa A de Claude, para pintar el mapa
    (seccion 3.1 del spec). Filtra por franja horaria porque el riesgo varia
    segun la hora del dia."""
    hour_bucket = hour if hour is not None else amba_now().hour
    zones = db.query(RiskZone).filter(RiskZone.hour_bucket == hour_bucket).all()
    return [
        RiskZoneOut(
            id=z.id,
            lat=z.cell_lat,
            lon=z.cell_lon,
            hour_bucket=z.hour_bucket,
            score=z.score,
            confidence=z.confidence,
            category=z.category,
            incident_count=z.incident_count,
        )
        for z in zones
    ]
