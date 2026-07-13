import httpx
from fastapi import APIRouter, HTTPException, Query

from ..config import settings
from ..schemas import RouteOut

router = APIRouter(prefix="/route", tags=["routing"])


@router.get("", response_model=RouteOut)
async def get_route(
    from_lat: float = Query(...),
    from_lon: float = Query(...),
    to_lat: float = Query(...),
    to_lon: float = Query(...),
):
    """Ruteo estandar (Fase 1, sin costo de seguridad/congestion todavia).
    Proxea al motor OSRM self-hosted."""
    coords = f"{from_lon},{from_lat};{to_lon},{to_lat}"
    url = f"{settings.osrm_url}/route/v1/driving/{coords}"
    params = {"overview": "full", "geometries": "geojson"}

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

    best_route = data["routes"][0]
    return RouteOut(
        distance_meters=best_route["distance"],
        duration_seconds=best_route["duration"],
        geometry=best_route["geometry"]["coordinates"],
    )
