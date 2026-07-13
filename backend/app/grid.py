GRID_PRECISION = 3  # ~111m de lado a la latitud de AMBA; funciona como proxy de
# "segmento de calle" para el MVP, sin necesitar map-matching contra OSM way IDs.


def grid_cell_center(lat: float, lon: float) -> tuple[float, float]:
    return round(lat, GRID_PRECISION), round(lon, GRID_PRECISION)
