#!/bin/bash
# Arranca los servicios aplicando los límites de RAM/CPU del .env.
# Sin --compatibility, Docker Compose ignora deploy.resources y los contenedores no usan la RAM configurada.
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."
docker compose --compatibility down "$@"
docker compose --compatibility up -d "$@"
echo ""
echo "Contenedores arrancados con límites del .env. Ver uso: docker stats"
