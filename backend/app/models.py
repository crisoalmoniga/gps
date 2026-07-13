from geoalchemy2 import Geometry
from sqlalchemy import Boolean, Column, DateTime, Float, Integer, String, UniqueConstraint
from sqlalchemy.sql import func

from .database import Base


class IncidentReport(Base):
    """Reporte de zona de riesgo. Se crea de inmediato con solo la ubicación
    (botón de 1 tap); el detalle se agrega despues via PATCH, sin bloquear."""

    __tablename__ = "incident_reports"

    id = Column(Integer, primary_key=True, index=True)
    location = Column(Geometry(geometry_type="POINT", srid=4326), nullable=False)

    incident_type = Column(String, nullable=True)
    severity = Column(String, nullable=True)
    description = Column(String, nullable=True)

    is_retroactive = Column(Boolean, default=False, nullable=False)
    occurred_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)

    # NULL = todavia no paso por la Capa A de Claude (ver routers/analysis.py).
    analyzed_at = Column(DateTime(timezone=True), nullable=True)


class TripPoint(Base):
    """Punto de velocidad GPS de un trayecto completado. Es la fuente de datos
    de congestion historica de la seccion 5 del spec ('Registrada por la app
    misma')."""

    __tablename__ = "trip_points"

    id = Column(Integer, primary_key=True, index=True)
    trip_id = Column(String, nullable=False, index=True)
    location = Column(Geometry(geometry_type="POINT", srid=4326), nullable=False)
    speed_kmh = Column(Float, nullable=False)
    recorded_at = Column(DateTime(timezone=True), nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)


class RiskZone(Base):
    """Score de riesgo agregado por celda de grilla + franja horaria, calculado
    por la Capa A de Claude a partir de reportes e incidentes de redes
    sociales (seccion 3.1 del spec)."""

    __tablename__ = "risk_zones"
    __table_args__ = (UniqueConstraint("cell_lat", "cell_lon", "hour_bucket", name="uq_risk_zone_cell_hour"),)

    id = Column(Integer, primary_key=True, index=True)
    cell = Column(Geometry(geometry_type="POINT", srid=4326), nullable=False)
    cell_lat = Column(Float, nullable=False, index=True)
    cell_lon = Column(Float, nullable=False, index=True)
    hour_bucket = Column(Integer, nullable=False)  # 0-23

    score = Column(Float, nullable=False)  # 0 (sin riesgo) a 100 (riesgo maximo)
    confidence = Column(Float, nullable=False)  # 0 a 1
    category = Column(String, nullable=True)
    incident_count = Column(Integer, nullable=False, default=1)

    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False)


class CongestionProfile(Base):
    """Perfil de congestion por celda de grilla + dia de la semana + hora,
    calculado deterministicamente (no via Claude) a partir de TripPoint."""

    __tablename__ = "congestion_profiles"
    __table_args__ = (
        UniqueConstraint("cell_lat", "cell_lon", "day_of_week", "hour", name="uq_congestion_cell_day_hour"),
    )

    id = Column(Integer, primary_key=True, index=True)
    cell_lat = Column(Float, nullable=False, index=True)
    cell_lon = Column(Float, nullable=False, index=True)
    day_of_week = Column(Integer, nullable=False)  # 0=domingo ... 6=sabado (EXTRACT(DOW) de Postgres)
    hour = Column(Integer, nullable=False)  # 0-23

    avg_speed_kmh = Column(Float, nullable=False)
    free_flow_speed_kmh = Column(Float, nullable=False)
    congestion_pct = Column(Float, nullable=False)  # 0 a 1: fraccion de velocidad perdida vs. free-flow
    sample_count = Column(Integer, nullable=False)

    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False)


class SocialMention(Base):
    """Posteo crudo de una cuenta comunitaria de X monitoreada (seccion 5.1).
    Pasa por la Capa A de Claude para extraer tipo/ubicacion/confianza antes
    de aplicarse como RiskZone."""

    __tablename__ = "social_mentions"
    __table_args__ = (UniqueConstraint("source_account", "external_id", name="uq_mention_account_external_id"),)

    id = Column(Integer, primary_key=True, index=True)
    source_account = Column(String, nullable=False)
    external_id = Column(String, nullable=False)  # id del posteo en la red, para deduplicar
    raw_text = Column(String, nullable=False)
    posted_at = Column(DateTime(timezone=True), nullable=True)
    scraped_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)

    incident_type = Column(String, nullable=True)
    location = Column(Geometry(geometry_type="POINT", srid=4326), nullable=True)
    confidence = Column(Float, nullable=True)

    # pending -> applied (se sumo como RiskZone) | discarded (ruido/baja confianza/sin ubicacion)
    status = Column(String, nullable=False, default="pending")
