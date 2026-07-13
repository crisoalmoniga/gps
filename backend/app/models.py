from geoalchemy2 import Geometry
from sqlalchemy import Boolean, Column, DateTime, Integer, String
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
