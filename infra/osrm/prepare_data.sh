#!/usr/bin/env bash
# Descarga el extracto de Argentina de Geofabrik, lo recorta al bounding box
# de AMBA (CABA + conurbano bonaerense) y genera los datos preprocesados de
# OSRM (perfil "driving" estandar, ver seccion 4 del spec para la funcion de
# costo custom que se sumara en fases posteriores).
#
# Requiere: docker, osmium-tool (apt install osmium-tool).
#
# La imagen de OSRM a usar es configurable via OSRM_IMAGE (default:
# osrm/osrm-backend, que solo existe para amd64). En arquitectura arm64
# (ej. Oracle Cloud Ampere) hay que compilarla antes desde codigo fuente
# — ver infra/oracle-cloud-init.sh — y pasar OSRM_IMAGE=rutasegura-osrm:<tag>.
set -euo pipefail

OSRM_IMAGE="${OSRM_IMAGE:-osrm/osrm-backend}"

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
osmium extract -b "$AMBA_BBOX" argentina-latest.osm.pbf -o amba.osm.pbf --overwrite

echo "Generando datos de ruteo OSRM (perfil driving) con la imagen $OSRM_IMAGE..."
docker run --rm -v "$DATA_DIR:/data" "$OSRM_IMAGE" \
  osrm-extract -p /opt/car.lua /data/amba.osm.pbf

docker run --rm -v "$DATA_DIR:/data" "$OSRM_IMAGE" \
  osrm-partition /data/amba.osrm

docker run --rm -v "$DATA_DIR:/data" "$OSRM_IMAGE" \
  osrm-customize /data/amba.osrm

echo "Listo. Los datos quedaron en $DATA_DIR — levantar con docker compose up osrm."
