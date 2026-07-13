from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from geoalchemy2.elements import WKTElement
from geoalchemy2.shape import to_shape
from sqlalchemy import func
from sqlalchemy.orm import Session

from ..database import get_db
from ..models import IncidentReport
from ..schemas import ReportCreate, ReportDetailUpdate, ReportOut

router = APIRouter(prefix="/reports", tags=["reports"])


def _to_out(report: IncidentReport) -> ReportOut:
    point = to_shape(report.location)
    return ReportOut(
        id=report.id,
        lat=point.y,
        lon=point.x,
        incident_type=report.incident_type,
        severity=report.severity,
        description=report.description,
        is_retroactive=report.is_retroactive,
        occurred_at=report.occurred_at,
        created_at=report.created_at,
    )


@router.post("", response_model=ReportOut, status_code=201)
def create_report(payload: ReportCreate, db: Session = Depends(get_db)):
    """Reporte de 1 tap: solo requiere ubicacion. El detalle se agrega despues,
    de forma opcional, via PATCH /reports/{id}."""
    report = IncidentReport(
        location=WKTElement(f"POINT({payload.lon} {payload.lat})", srid=4326),
        is_retroactive=payload.is_retroactive,
        occurred_at=payload.occurred_at,
    )
    db.add(report)
    db.commit()
    db.refresh(report)
    return _to_out(report)


@router.patch("/{report_id}", response_model=ReportOut)
def update_report_detail(report_id: int, payload: ReportDetailUpdate, db: Session = Depends(get_db)):
    report = db.query(IncidentReport).get(report_id)
    if report is None:
        raise HTTPException(status_code=404, detail="Reporte no encontrado")

    for field, value in payload.model_dump(exclude_unset=True).items():
        setattr(report, field, value)

    db.commit()
    db.refresh(report)
    return _to_out(report)


@router.get("", response_model=list[ReportOut])
def list_reports(
    min_lat: Optional[float] = Query(None),
    min_lon: Optional[float] = Query(None),
    max_lat: Optional[float] = Query(None),
    max_lon: Optional[float] = Query(None),
    db: Session = Depends(get_db),
):
    """Lista reportes, opcionalmente filtrados por bounding box (viewport del mapa)."""
    query = db.query(IncidentReport)

    if None not in (min_lat, min_lon, max_lat, max_lon):
        envelope = func.ST_MakeEnvelope(min_lon, min_lat, max_lon, max_lat, 4326)
        query = query.filter(func.ST_Within(IncidentReport.location, envelope))

    reports = query.order_by(IncidentReport.created_at.desc()).limit(1000).all()
    return [_to_out(r) for r in reports]
