from datetime import datetime, timezone

from fastapi import APIRouter, Depends
from geoalchemy2.elements import WKTElement
from geoalchemy2.shape import to_shape
from sqlalchemy import text
from sqlalchemy.orm import Session

from .. import claude_client
from ..config import settings
from ..database import get_db
from ..geocoding import geocode
from ..grid import GRID_PRECISION, grid_cell_center
from ..models import CongestionProfile, IncidentReport, RiskZone, SocialMention
from ..timezone_utils import amba_now, to_amba_hour

router = APIRouter(prefix="/analysis", tags=["analysis"])

BATCH_LIMIT = 50


def _upsert_risk_zone(db: Session, lat: float, lon: float, hour_bucket: int, score: float, confidence: float, category: str) -> None:
    cell_lat, cell_lon = grid_cell_center(lat, lon)
    zone = (
        db.query(RiskZone)
        .filter(RiskZone.cell_lat == cell_lat, RiskZone.cell_lon == cell_lon, RiskZone.hour_bucket == hour_bucket)
        .first()
    )
    if zone is None:
        db.add(
            RiskZone(
                cell=WKTElement(f"POINT({cell_lon} {cell_lat})", srid=4326),
                cell_lat=cell_lat,
                cell_lon=cell_lon,
                hour_bucket=hour_bucket,
                score=score,
                confidence=confidence,
                category=category,
                incident_count=1,
            )
        )
    else:
        total = zone.incident_count + 1
        zone.score = (zone.score * zone.incident_count + score) / total
        zone.confidence = (zone.confidence * zone.incident_count + confidence) / total
        zone.category = category
        zone.incident_count = total
    db.flush()


@router.post("/classify-reports")
def classify_pending_reports(db: Session = Depends(get_db)):
    """Capa A: clasifica reportes de usuarios que todavia no pasaron por
    Claude (seccion 3.1 del spec). Pensado para correr periodicamente (cron)."""
    pending = db.query(IncidentReport).filter(IncidentReport.analyzed_at.is_(None)).limit(BATCH_LIMIT).all()

    classified = 0
    for report in pending:
        point = to_shape(report.location)
        try:
            result = claude_client.classify_report(report.description, report.incident_type, report.severity)
        except Exception:
            continue  # se reintenta en la proxima corrida

        hour_bucket = to_amba_hour(report.occurred_at or report.created_at)
        _upsert_risk_zone(
            db,
            point.y,
            point.x,
            hour_bucket,
            result["score"],
            result["confidence"],
            result["category"],
        )
        report.analyzed_at = datetime.now(timezone.utc)
        classified += 1

    db.commit()
    return {"classified": classified, "pending_remaining": len(pending) - classified}


@router.post("/process-mentions")
def process_pending_mentions(db: Session = Depends(get_db)):
    """Capa A: extrae datos estructurados de las menciones de X pendientes y,
    si son de confianza suficiente y tienen ubicacion, las suma como
    RiskZone (seccion 5.1 del spec). Mitigacion de ruido: descarta lo que
    Claude marca como no-incidente o de baja confianza."""
    pending = db.query(SocialMention).filter(SocialMention.status == "pending").limit(BATCH_LIMIT).all()

    processed = 0
    for mention in pending:
        try:
            result = claude_client.extract_mention(mention.raw_text, mention.source_account)
        except Exception:
            continue

        mention.confidence = result.get("confidence", 0.0)
        mention.incident_type = result.get("incident_type")

        if not result.get("is_incident") or mention.confidence < settings.mention_confidence_threshold:
            mention.status = "discarded"
            processed += 1
            continue

        location_text = result.get("location_text")
        point = geocode(location_text) if location_text else None
        if point is None:
            mention.status = "discarded"  # sin ubicacion no se puede aplicar al mapa
            processed += 1
            continue

        lat, lon = point
        mention.location = WKTElement(f"POINT({lon} {lat})", srid=4326)
        # Score base escalado por confianza: una mencion de red social nunca
        # pesa tanto como un reporte directo de usuario verificado.
        score = 40 + 60 * mention.confidence
        hour_bucket = to_amba_hour(mention.posted_at or datetime.now(timezone.utc))
        _upsert_risk_zone(db, lat, lon, hour_bucket, score, mention.confidence, mention.incident_type or "otro")
        mention.status = "applied"
        processed += 1

    db.commit()
    return {"processed": processed, "pending_remaining": len(pending) - processed}


@router.post("/congestion-profiles")
def recompute_congestion_profiles(db: Session = Depends(get_db)):
    """Agrega los trip_points historicos en perfiles de congestion por
    celda/dia/hora. Es un calculo estadistico deterministico (seccion 3.1:
    'Detección de patrones de congestión'), no usa Claude — el valor de
    Claude en Capa A es sobre texto no estructurado, no sobre numeros."""
    # recorded_at se guarda en UTC (timestamptz); se convierte a hora local
    # de AMBA antes de extraer dia/hora, porque lo que importa es la hora
    # pico real que vive el usuario, no la hora UTC del servidor.
    rows = db.execute(
        text(
            """
            SELECT
                round(ST_Y(location)::numeric, :precision)::float AS cell_lat,
                round(ST_X(location)::numeric, :precision)::float AS cell_lon,
                EXTRACT(DOW FROM recorded_at AT TIME ZONE 'America/Argentina/Buenos_Aires')::int AS day_of_week,
                EXTRACT(HOUR FROM recorded_at AT TIME ZONE 'America/Argentina/Buenos_Aires')::int AS hour,
                avg(speed_kmh) AS avg_speed,
                count(*) AS sample_count
            FROM trip_points
            GROUP BY 1, 2, 3, 4
            """
        ),
        {"precision": GRID_PRECISION},
    ).fetchall()

    free_flow_by_cell: dict[tuple[float, float], float] = {}
    for row in rows:
        key = (row.cell_lat, row.cell_lon)
        free_flow_by_cell[key] = max(free_flow_by_cell.get(key, 0.0), row.avg_speed)

    for row in rows:
        free_flow = free_flow_by_cell[(row.cell_lat, row.cell_lon)]
        congestion_pct = max(0.0, 1 - (row.avg_speed / free_flow)) if free_flow else 0.0

        profile = (
            db.query(CongestionProfile)
            .filter(
                CongestionProfile.cell_lat == row.cell_lat,
                CongestionProfile.cell_lon == row.cell_lon,
                CongestionProfile.day_of_week == row.day_of_week,
                CongestionProfile.hour == row.hour,
            )
            .first()
        )
        if profile is None:
            db.add(
                CongestionProfile(
                    cell_lat=row.cell_lat,
                    cell_lon=row.cell_lon,
                    day_of_week=row.day_of_week,
                    hour=row.hour,
                    avg_speed_kmh=row.avg_speed,
                    free_flow_speed_kmh=free_flow,
                    congestion_pct=congestion_pct,
                    sample_count=row.sample_count,
                )
            )
        else:
            profile.avg_speed_kmh = row.avg_speed
            profile.free_flow_speed_kmh = free_flow
            profile.congestion_pct = congestion_pct
            profile.sample_count = row.sample_count

    db.commit()
    return {"cells_updated": len(rows)}
