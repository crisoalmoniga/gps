from fastapi import APIRouter, Depends
from geoalchemy2.elements import WKTElement
from sqlalchemy.orm import Session

from ..database import get_db
from ..models import TripPoint
from ..schemas import TripUpload

router = APIRouter(prefix="/trips", tags=["trips"])


@router.post("", status_code=201)
def upload_trip(payload: TripUpload, db: Session = Depends(get_db)):
    """Sube el historial de velocidad de un trayecto ya completado, para
    construir perfiles de congestion (seccion 5 del spec: congestion
    historica 'registrada por la app misma')."""
    points = [
        TripPoint(
            trip_id=payload.trip_id,
            location=WKTElement(f"POINT({p.lon} {p.lat})", srid=4326),
            speed_kmh=p.speed_kmh,
            recorded_at=p.recorded_at,
        )
        for p in payload.points
    ]
    db.add_all(points)
    db.commit()
    return {"points_saved": len(points)}
