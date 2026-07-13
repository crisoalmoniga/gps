from typing import Optional

import httpx

from .config import settings

NOMINATIM_URL = "https://nominatim.openstreetmap.org/search"


def geocode(query: str) -> Optional[tuple[float, float]]:
    """Geocodifica texto libre (ej. 'Av. Rivadavia y Boyaca') a (lat, lon)
    usando Nominatim, para ubicar menciones de redes sociales en el mapa
    (seccion 5.1 del spec). Devuelve None si no encuentra nada."""
    params = {
        "q": query,
        "format": "json",
        "limit": "1",
        "countrycodes": "ar",
        "viewbox": "-59.3,-34.2,-58.0,-35.3",
        "bounded": "1",
    }
    headers = {"User-Agent": f"RutaSegura/0.1 ({settings.osrm_url})"}

    try:
        response = httpx.get(NOMINATIM_URL, params=params, headers=headers, timeout=10.0)
    except httpx.RequestError:
        return None

    if response.status_code != 200:
        return None

    results = response.json()
    if not results:
        return None

    return float(results[0]["lat"]), float(results[0]["lon"])
