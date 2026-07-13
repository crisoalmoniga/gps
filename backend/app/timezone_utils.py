from datetime import datetime
from zoneinfo import ZoneInfo

# AMBA es el area de operacion (seccion 0 del spec). Los "hour_bucket"/
# "day_of_week" de RiskZone y CongestionProfile representan la hora local,
# no UTC, porque lo que importa es la hora pico real que vive el usuario.
AMBA_TZ = ZoneInfo("America/Argentina/Buenos_Aires")


def amba_now() -> datetime:
    return datetime.now(AMBA_TZ)


def to_amba_hour(dt: datetime) -> int:
    return dt.astimezone(AMBA_TZ).hour
