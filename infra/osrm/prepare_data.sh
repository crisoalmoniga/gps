#!/usr/bin/env bash
# Descarga el extracto de Argentina de Geofabrik, lo recorta al bounding box
# de AMBA (CABA + conurbano bonaerense) y genera los datos preprocesados de
# OSRM (perfil "driving" estandar, ver seccion 4 del spec para la funcion de
# costo custom que se sumara en fases posteriores).
#
# Requiere: docker
set -euo pipefail

DATA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/data"
mkdir -p "$DATA_DIR"
cd "$DATA_DIR"

# Bounding box aproximado de AMBA (min_lon,min_lat,max_lon,max_lat).
# Ajustar si hace falta mas cobertura.
AMBA_BBOX="-59.3,-35.3,-58.0,-34.2"

if [ ! -f argentina-latest.osm.pbf ]; then
  echo "Descargando extracto de Argentina desde Geofabrik..."
  curl -L -o argentina-latest.osm.pbf \
    https://download.geofabrik.de/south-america/argentina-latest.osm.pbf
fi

echo "Recortando al bounding box de AMBA ($AMBA_BBOX)..."
docker run --rm -v "$DATA_DIR:/data" osmium/osmium-tool \
  osmium extract -b "$AMBA_BBOX" /data/argentina-latest.osm.pbf -o /data/amba.osm.pbf --overwrite

echo "Generando datos de ruteo OSRM (perfil driving)..."
docker run --rm -v "$DATA_DIR:/data" osrm/osrm-backend \
  osrm-extract -p /opt/car.lua /data/amba.osm.pbf

docker run --rm -v "$DATA_DIR:/data" osrm/osrm-backend \
  osrm-partition /data/amba.osrm

docker run --rm -v "$DATA_DIR:/data" osrm/osrm-backend \
  osrm-customize /data/amba.osrm

echo "Listo. Los datos quedaron en $DATA_DIR — levantar con docker compose up osrm."
