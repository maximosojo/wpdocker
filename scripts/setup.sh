#!/bin/bash
# Genera la configuración de Nginx desde .env y prepara directorios.
# Ejecutar desde la raíz del proyecto. En servidores nuevos: crear .env → ./scripts/setup.sh → docker-compose up -d

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

# Comprobar que estamos en el proyecto
if [ ! -f "docker-compose.yml" ]; then
  echo -e "${RED}Error: Ejecuta este script desde la raíz del proyecto (donde está docker-compose.yml).${NC}"
  exit 1
fi

# Crear .env si no existe
if [ ! -f ".env" ]; then
  if [ -f ".env.example" ]; then
    cp .env.example .env
    echo -e "${YELLOW}Se creó .env desde .env.example.${NC}"
    echo -e "${YELLOW}Edita .env con tu dominio, contraseñas y opciones, luego ejecuta de nuevo:${NC}"
    echo "  ./scripts/setup.sh"
    exit 1
  else
    echo -e "${RED}Error: No existe .env ni .env.example. Crea un .env con al menos DOMAIN y las contraseñas de MySQL.${NC}"
    exit 1
  fi
fi

# Cargar variables desde .env (solo las necesarias para validación y envsubst)
set -a
# shellcheck source=/dev/null
. ./.env
set +a

DOMAIN="${DOMAIN:-}"
if [ -z "$DOMAIN" ]; then
  echo -e "${RED}Error: Define DOMAIN en .env (ej: DOMAIN=midominio.com o DOMAIN=localhost).${NC}"
  exit 1
fi

# Validar variables requeridas para Docker
if [ -z "${MYSQL_ROOT_PASSWORD:-}" ] || [ -z "${MYSQL_PASSWORD:-}" ]; then
  echo -e "${RED}Error: Define MYSQL_ROOT_PASSWORD y MYSQL_PASSWORD en .env antes de arrancar.${NC}"
  exit 1
fi
if [ "$MYSQL_PASSWORD" = "$MYSQL_ROOT_PASSWORD" ] && [ -n "$MYSQL_PASSWORD" ]; then
  echo -e "${YELLOW}Recomendación: usa una contraseña distinta para MYSQL_USER (MYSQL_PASSWORD) y root (MYSQL_ROOT_PASSWORD).${NC}"
fi
export DOMAIN

# Generar nginx/conf.d/wordpress.conf desde la plantilla
TEMPLATE="nginx/conf.d/wordpress.conf.template"
OUTPUT="nginx/conf.d/wordpress.conf"
if [ ! -f "$TEMPLATE" ]; then
  echo -e "${RED}Error: No existe $TEMPLATE${NC}"
  exit 1
fi

if command -v envsubst >/dev/null 2>&1; then
  envsubst '\$DOMAIN' < "$TEMPLATE" > "$OUTPUT"
  echo -e "${GREEN}✓ Generado $OUTPUT (server_name: $DOMAIN www.$DOMAIN)${NC}"
else
  # Fallback sin envsubst (macOS puede no tenerlo por defecto)
  sed "s/\${DOMAIN}/$DOMAIN/g" "$TEMPLATE" > "$OUTPUT"
  echo -e "${GREEN}✓ Generado $OUTPUT con sed (server_name: $DOMAIN www.$DOMAIN)${NC}"
fi

# Directorios de backup
mkdir -p backups/db backups/wp
echo -e "${GREEN}✓ Directorios backups/db y backups/wp listos${NC}"

# Comprobar Docker (opcional, no bloqueante)
if ! command -v docker >/dev/null 2>&1; then
  echo -e "${YELLOW}Advertencia: Docker no está instalado o no está en el PATH.${NC}"
elif ! docker info >/dev/null 2>&1; then
  echo -e "${YELLOW}Advertencia: Docker no está en ejecución o no tienes permisos.${NC}"
else
  echo -e "${GREEN}✓ Docker disponible${NC}"
fi

echo ""
echo -e "${GREEN}Configuración lista. Para arrancar los servicios:${NC}"
echo "  docker-compose up -d"
echo ""
echo "Para ver logs: docker-compose logs -f"
