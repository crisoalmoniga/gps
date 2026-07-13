import math
from datetime import datetime

import httpx
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from ..config import settings
from ..database import get_db
from ..grid import grid_cell_center
from ..models import CongestionProfile, RiskZone
from ..schemas import RouteOut
from ..timezone_utils import amba_now

router = APIRouter(prefix="/route", tags=["routing"])

# Pseudo-costo: segundos añadidos por punto de score de riesgo (0-100) cuando
# peso_seguridad=1. Es un punto de partida para el MVP (seccion 4 del spec);
# se puede recalibrar una vez que haya datos reales de reportes.
RISK_SECONDS_PER_POINT = 5.0


@router.get("", response_model=RouteOut)
async def get_route(
    from_lat: float = Query(...),
    from_lon: float = Query(...),
    to_lat: float = Query(...),
    to_lon: float = Query(...),
    peso_seguridad: float = Query(1.0, ge=0, description="Ajustable por el usuario (slider) o por el copiloto"),
    peso_congestion: float = Query(1.0, ge=0),
    db: Session = Depends(get_db),
):
    """Pide alternativas a OSRM (ruteo estandar) y elige la de menor costo
    combinado tiempo + seguridad + congestion (formula de la seccion 4 del
    spec), aproximada por muestreo de la geometria en vez de recalcular el
    grafo de OSRM por pedido."""
    coords = f"{from_lon},{from_lat};{to_lon},{to_lat}"
    url = f"{settings.osrm_url}/route/v1/driving/{coords}"
    params = {"overview": "full", "geometries": "geojson", "alternatives": "true"}

    async with httpx.AsyncClient(timeout=10.0) as client:
        try:
            response = await client.get(url, params=params)
        except httpx.RequestError as exc:
            raise HTTPException(status_code=503, detail=f"Motor de ruteo no disponible: {exc}") from exc

    if response.status_code != 200:
        raise HTTPException(status_code=502, detail="Error del motor de ruteo")

    data = response.json()
    if data.get("code") != "Ok" or not data.get("routes"):
        raise HTTPException(status_code=404, detail="No se encontro una ruta")

    now = amba_now()
    best_route = None
    best_avg_risk = 0.0
    best_avg_congestion = 0.0
    best_cost = math.inf

    for route in data["routes"]:
        coordinates = route["geometry"]["coordinates"]
        avg_risk, avg_congestion = _score_route(db, coordinates, now)
        combined_cost = (
            route["duration"]
            + peso_seguridad * avg_risk * RISK_SECONDS_PER_POINT
            + peso_congestion * avg_congestion * route["duration"]
        )
        if combined_cost < best_cost:
            best_cost = combined_cost
            best_route = route
            best_avg_risk = avg_risk
            best_avg_congestion = avg_congestion

    return RouteOut(
        distance_meters=best_route["distance"],
        duration_seconds=best_route["duration"],
        geometry=best_route["geometry"]["coordinates"],
        avg_risk_score=best_avg_risk,
        avg_congestion_pct=best_avg_congestion,
    )


def _score_route(db: Session, coordinates: list[list[float]], now: datetime) -> tuple[float, float]:
    # Muestrea la geometria (max ~25 puntos) para no golpear la base con cada
    # vertice en rutas largas.
    step = max(1, len(coordinates) // 25)
    sample = coordinates[::step]

    hour_bucket = now.hour
    day_of_week = (now.weekday() + 1) % 7  # Postgres EXTRACT(DOW): domingo=0, lunes=1...

    risk_scores = []
    congestion_values = []
    for lon, lat in sample:
        cell_lat, cell_lon = grid_cell_center(lat, lon)

        zone = (
            db.query(RiskZone)
            .filter(RiskZone.cell_lat == cell_lat, RiskZone.cell_lon == cell_lon, RiskZone.hour_bucket == hour_bucket)
            .first()
        )
        if zone:
            risk_scores.append(zone.score)

        profile = (
            db.query(CongestionProfile)
            .filter(
                CongestionProfile.cell_lat == cell_lat,
                CongestionProfile.cell_lon == cell_lon,
                CongestionProfile.day_of_week == day_of_week,
                CongestionProfile.hour == hour_bucket,
            )
            .first()
        )
        if profile:
            congestion_values.append(profile.congestion_pct)

    avg_risk = sum(risk_scores) / len(risk_scores) if risk_scores else 0.0
    avg_congestion = sum(congestion_values) / len(congestion_values) if congestion_values else 0.0
    return avg_risk, avg_congestion
