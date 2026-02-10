#!/bin/bash
# Backup de WordPress y base de datos. Usa .env para credenciales y nombre del proyecto.
# Uso: ./scripts/backup.sh [nombre_backup]
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
  echo -e "${RED}Error: Ejecuta desde la raíz del proyecto y asegúrate de tener .env (ej. tras ./scripts/setup.sh).${NC}"
  exit 1
fi

# Cargar .env para nombres de contenedor y credenciales
set -a
# shellcheck source=/dev/null
. ./.env
set +a

CONTAINER_DB="${COMPOSE_PROJECT_NAME:-wpdocker}_wordpress_mysql"
CONTAINER_WP="${COMPOSE_PROJECT_NAME:-wpdocker}_wordpress_app"
DB_USER="${MYSQL_USER:-wordpress_user}"
DB_PASS="${MYSQL_PASSWORD:?Define MYSQL_PASSWORD en .env}"
DB_NAME="${MYSQL_DATABASE:-wordpress_db}"

BACKUP_DIR="./backups"
DB_BACKUP_DIR="$BACKUP_DIR/db"
WP_BACKUP_DIR="$BACKUP_DIR/wp"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME=${1:-backup_${TIMESTAMP}}

mkdir -p "$DB_BACKUP_DIR"
mkdir -p "$WP_BACKUP_DIR"

echo -e "${GREEN}Iniciando backup de WordPress...${NC}"

# 1. Backup de la base de datos
echo -e "${YELLOW}Realizando backup de la base de datos...${NC}"
if docker-compose exec -T db mysqldump -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" | gzip > "$DB_BACKUP_DIR/${BACKUP_NAME}.sql.gz"; then
  echo -e "${GREEN}✓ Backup de base de datos completado: ${DB_BACKUP_DIR}/${BACKUP_NAME}.sql.gz${NC}"
else
  echo -e "${RED}✗ Error al hacer backup de la base de datos${NC}"
  exit 1
fi

# 2. Backup de archivos de WordPress
echo -e "${YELLOW}Realizando backup de archivos de WordPress...${NC}"
if docker-compose exec -T wordpress tar -czf /backups/${BACKUP_NAME}.tar.gz -C /var/www/html . ; then
  docker cp "${CONTAINER_WP}:/backups/${BACKUP_NAME}.tar.gz" "$WP_BACKUP_DIR/${BACKUP_NAME}.tar.gz"
  docker-compose exec -T wordpress rm -f /backups/${BACKUP_NAME}.tar.gz
  echo -e "${GREEN}✓ Backup de WordPress completado: ${WP_BACKUP_DIR}/${BACKUP_NAME}.tar.gz${NC}"
else
  echo -e "${RED}✗ Error al hacer backup de WordPress${NC}"
  exit 1
fi

# Metadatos
cat > "$BACKUP_DIR/${BACKUP_NAME}.info" << EOF
Backup realizado el: $(date)
Nombre: ${BACKUP_NAME}
Base de datos: ${DB_BACKUP_DIR}/${BACKUP_NAME}.sql.gz
WordPress: ${WP_BACKUP_DIR}/${BACKUP_NAME}.tar.gz
EOF

echo -e "${GREEN}✓ Backup completo creado: ${BACKUP_NAME}${NC}"
echo -e "${YELLOW}Archivos:${NC}"
echo -e "  - Base de datos: ${DB_BACKUP_DIR}/${BACKUP_NAME}.sql.gz"
echo -e "  - WordPress: ${WP_BACKUP_DIR}/${BACKUP_NAME}.tar.gz"
echo -e "  - Info: ${BACKUP_DIR}/${BACKUP_NAME}.info"
