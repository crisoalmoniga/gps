#!/usr/bin/env bash
# Dispara la Capa A de Claude y el recalculo de congestion. Pensado para
# correr por cron (seccion 3.1 del spec: "cada noche, o cada vez que entran
# N reportes nuevos"). Ejemplo de crontab (una vez por noche a las 3am):
#
#   0 3 * * * /path/a/run_analysis.sh >> /var/log/rutasegura-analysis.log 2>&1
set -euo pipefail

BACKEND_URL="${BACKEND_URL:-http://localhost:8000}"

echo "[$(date -Iseconds)] Clasificando reportes pendientes..."
curl -sf -X POST "$BACKEND_URL/analysis/classify-reports"
echo

echo "[$(date -Iseconds)] Procesando menciones de X pendientes..."
curl -sf -X POST "$BACKEND_URL/analysis/process-mentions"
echo

echo "[$(date -Iseconds)] Recalculando perfiles de congestion..."
curl -sf -X POST "$BACKEND_URL/analysis/congestion-profiles"
echo
