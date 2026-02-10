#!/bin/bash
# Restaura backup de WordPress y base de datos. Usa .env para credenciales y nombre del proyecto.
# Uso: ./scripts/restore.sh <nombre_backup>
# Ejecutar desde la raíz del proyecto.

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

if [ ! -f "docker-compose.yml" ] || [ ! -f ".env" ]; then
  echo -e "${RED}Error: Ejecuta desde la raíz del proyecto y asegúrate de tener .env.${NC}"
  exit 1
fi

# Cargar .env
set -a
# shellcheck source=/dev/null
. ./.env
set +a

CONTAINER_WP="${COMPOSE_PROJECT_NAME:-wpdocker}_wordpress_app"
DB_USER="${MYSQL_USER:-wordpress_user}"
DB_PASS="${MYSQL_PASSWORD:?Define MYSQL_PASSWORD en .env}"
DB_NAME="${MYSQL_DATABASE:-wordpress_db}"

BACKUP_DIR="./backups"
DB_BACKUP_DIR="$BACKUP_DIR/db"
WP_BACKUP_DIR="$BACKUP_DIR/wp"

if [ -z "$1" ]; then
  echo -e "${RED}Error: Debes especificar el nombre del backup${NC}"
  echo "Uso: ./scripts/restore.sh <nombre_backup>"
  echo "Backups disponibles:"
  ls -1 "$BACKUP_DIR"/*.info 2>/dev/null | xargs -n1 basename | sed 's/.info$//' || echo "  No hay backups disponibles"
  exit 1
fi

BACKUP_NAME=$1
DB_BACKUP_FILE="$DB_BACKUP_DIR/${BACKUP_NAME}.sql.gz"
WP_BACKUP_FILE="$WP_BACKUP_DIR/${BACKUP_NAME}.tar.gz"

if [ ! -f "$DB_BACKUP_FILE" ]; then
  echo -e "${RED}Error: No se encuentra el backup de base de datos: ${DB_BACKUP_FILE}${NC}"
  exit 1
fi
if [ ! -f "$WP_BACKUP_FILE" ]; then
  echo -e "${RED}Error: No se encuentra el backup de WordPress: ${WP_BACKUP_FILE}${NC}"
  exit 1
fi

echo -e "${YELLOW}⚠️  ADVERTENCIA: Este proceso restaurará la base de datos y los archivos de WordPress.${NC}"
echo -e "${YELLOW}Esto sobrescribirá los datos actuales.${NC}"
read -p "¿Estás seguro de que quieres continuar? (s/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Ss]$ ]]; then
  echo "Restauración cancelada."
  exit 0
fi

echo -e "${GREEN}Iniciando restauración desde: ${BACKUP_NAME}${NC}"

# 1. Restaurar base de datos
echo -e "${YELLOW}Restaurando base de datos...${NC}"
if ! gunzip < "$DB_BACKUP_FILE" | docker-compose exec -T db mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME"; then
  echo -e "${RED}✗ Error al restaurar la base de datos${NC}"
  exit 1
fi
echo -e "${GREEN}✓ Base de datos restaurada${NC}"

# 2. Detener WordPress
echo -e "${YELLOW}Deteniendo WordPress temporalmente...${NC}"
docker-compose stop wordpress

# 3. Restaurar archivos con contenedor temporal (volumen = mismo que en docker-compose)
echo -e "${YELLOW}Restaurando archivos de WordPress...${NC}"
WP_VOLUME="wpdocker_wp_data"
docker run --rm \
  -v "$WP_VOLUME:/var/www/html" \
  -v "$(pwd)/$WP_BACKUP_FILE:/backups/restore.tar.gz:ro" \
  wordpress:latest \
  sh -c "cd /var/www/html && rm -rf * .[^.]* 2>/dev/null || true && tar -xzf /backups/restore.tar.gz -C . && chown -R www-data:www-data ."

# 4. Reiniciar WordPress
echo -e "${YELLOW}Reiniciando WordPress...${NC}"
docker-compose start wordpress

echo -e "${GREEN}✓ Restauración completada exitosamente${NC}"
echo -e "${YELLOW}Nota: Puede que necesites limpiar la caché de WordPress desde el panel de administración.${NC}"
