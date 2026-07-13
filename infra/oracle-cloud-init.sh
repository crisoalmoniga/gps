#!/bin/bash
# Bootstrap de RutaSegura para una VM Ampere A1 (arm64) de Oracle Cloud Free
# Tier. Pegar este script completo en el campo "Cloud-init script" / "User
# data" al crear la instancia (Ubuntu 22.04 o 24.04 aarch64). Corre una sola
# vez, en el primer arranque, como root.
#
# Por que compilar OSRM desde codigo fuente: la imagen oficial
# osrm/osrm-backend en Docker Hub solo existe para amd64. Las VM Ampere son
# arm64, asi que se compila el propio Dockerfile-debian del proyecto (que
# ya soporta arm64 nativamente via vcpkg) directamente en esta maquina.
# Esto tarda bastante (compila Boost/TBB desde cero) — contar 30-90 minutos
# para que el stack completo quede arriba. Progreso en /var/log/rutasegura-setup.log.
set -euo pipefail
exec > >(tee -a /var/log/rutasegura-setup.log) 2>&1

echo "=== RutaSegura: bootstrap iniciado $(date -Iseconds) ==="

REPO_URL="https://github.com/crisoalmoniga/gps.git"
BRANCH="claude/app-development-xb04e9"
APP_DIR="/opt/rutasegura"
OSRM_TAG="v26.6.2"
OSRM_IMAGE="rutasegura-osrm:${OSRM_TAG}"

export DEBIAN_FRONTEND=noninteractive

echo "--- Instalando dependencias base ---"
apt-get update -y
apt-get install -y --no-install-recommends ca-certificates curl gnupg git osmium-tool

echo "--- Instalando Docker Engine ---"
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
ARCH=$(dpkg --print-architecture)
CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${CODENAME} stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker

echo "--- Abriendo el puerto 8000 en el firewall local (ademas de la Security List/NSG de OCI) ---"
# Las imagenes Ubuntu de Oracle traen reglas de iptables que bloquean todo
# lo que no sea SSH por defecto, ademas del filtrado a nivel de red (Security
# List / Network Security Group) que se configura desde la consola de OCI.
iptables -I INPUT 6 -m state --state NEW -p tcp --dport 8000 -j ACCEPT || true
netfilter-persistent save 2>/dev/null || (mkdir -p /etc/iptables && iptables-save > /etc/iptables/rules.v4) || true

echo "--- Clonando el repositorio de la app ---"
git clone --branch "$BRANCH" --single-branch "$REPO_URL" "$APP_DIR"

echo "--- Compilando OSRM ${OSRM_TAG} desde codigo fuente para arm64 (puede tardar bastante) ---"
BUILD_DIR="/opt/osrm-backend-src"
git clone --branch "$OSRM_TAG" --depth 1 https://github.com/Project-OSRM/osrm-backend.git "$BUILD_DIR"
docker build -f "$BUILD_DIR/docker/Dockerfile-debian" -t "$OSRM_IMAGE" "$BUILD_DIR"
rm -rf "$BUILD_DIR"

echo "--- Generando datos de ruteo OSRM para AMBA ---"
cd "$APP_DIR/infra"
OSRM_IMAGE="$OSRM_IMAGE" ./osrm/prepare_data.sh

echo "--- Guardando configuracion ---"
cat > "$APP_DIR/infra/.env" <<EOF
OSRM_IMAGE=${OSRM_IMAGE}
EOF

echo "--- Levantando el stack (postgres, osrm, backend) ---"
docker compose up -d --build

echo "=== RutaSegura: bootstrap terminado $(date -Iseconds) ==="
echo "Backend deberia responder en http://<IP-PUBLICA-DE-ESTA-VM>:8000/health"
