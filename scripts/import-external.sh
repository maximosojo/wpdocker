#!/bin/bash
# Importa una base de datos .sql (o .sql.gz) y una carpeta wp-content desde un .tar.gz
# procedentes de un WordPress NO dockerizado.
#
# Uso:
#   ./scripts/import-external.sh <archivo.sql|archivo.sql.gz> <archivo_wp-content.tar.gz>
#
# Ejemplo:
#   ./scripts/import-external.sh mi_backup.sql wp-content.tar.gz
#   ./scripts/import-external.sh backups/db/export.sql.gz backups/wp-content.tar.gz
#
# El .tar.gz de wp-content puede ser:
#   - Contenido directo de wp-content (plugins/, themes/, uploads/, etc.)
#   - O un archivo que al descomprimir tiene una carpeta "wp-content" con eso dentro
#
# Ejecutar desde la raíz del proyecto (donde está docker-compose.yml).

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
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

CONTAINER_DB="${COMPOSE_PROJECT_NAME:-wpdocker}_wordpress_mysql"
DB_USER="${MYSQL_USER:-wordpress_user}"
DB_PASS="${MYSQL_PASSWORD:?Define MYSQL_PASSWORD en .env}"
DB_NAME="${MYSQL_DATABASE:-wordpress_db}"
DB_ROOT_PASS="${MYSQL_ROOT_PASSWORD:?Define MYSQL_ROOT_PASSWORD en .env}"
VOLUME_WP="${COMPOSE_PROJECT_NAME:-wpdocker}_wp_data"

if [ -z "$1" ] || [ -z "$2" ]; then
  echo -e "${RED}Uso: $0 <archivo.sql|archivo.sql.gz> <archivo_wp-content.tar.gz>${NC}"
  echo ""
  echo "Ejemplo:"
  echo "  $0 mi_export.sql wp-content.tar.gz"
  echo "  $0 backups/db/sitio_antiguo.sql.gz backups/wp-content.tar.gz"
  echo ""
  echo "Asegúrate de que los archivos existan y que Docker esté corriendo (docker compose up -d)."
  exit 1
fi

SQL_FILE="$1"
WP_TAR_FILE="$2"

# Resolver rutas absolutas si son relativas
[ "${SQL_FILE#/}" = "$SQL_FILE" ] && SQL_FILE="$(pwd)/$SQL_FILE"
[ "${WP_TAR_FILE#/}" = "$WP_TAR_FILE" ] && WP_TAR_FILE="$(pwd)/$WP_TAR_FILE"

if [ ! -f "$SQL_FILE" ]; then
  echo -e "${RED}Error: No se encuentra el archivo SQL: $SQL_FILE${NC}"
  exit 1
fi
if [ ! -f "$WP_TAR_FILE" ]; then
  echo -e "${RED}Error: No se encuentra el archivo wp-content: $WP_TAR_FILE${NC}"
  exit 1
fi

echo -e "${BLUE}=== Importación desde backup externo ===${NC}"
echo -e "Base de datos: ${SQL_FILE}"
echo -e "wp-content:    ${WP_TAR_FILE}"
echo ""
echo -e "${YELLOW}Esto sobrescribirá la base de datos y wp-content actuales.${NC}"
read -p "¿Continuar? (s/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Ss]$ ]]; then
  echo "Importación cancelada."
  exit 0
fi

# 1. Importar base de datos
echo -e "${YELLOW}Importando base de datos...${NC}"
if [[ "$SQL_FILE" == *.gz ]]; then
  if ! gunzip -c "$SQL_FILE" | docker compose exec -T db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME"; then
    echo -e "${RED}✗ Error al importar la base de datos (archivo .sql.gz)${NC}"
    exit 1
  fi
else
  if ! docker compose exec -T db mysql -u root -p"$DB_ROOT_PASS" "$DB_NAME" < "$SQL_FILE"; then
    echo -e "${RED}✗ Error al importar la base de datos (archivo .sql)${NC}"
    exit 1
  fi
fi
echo -e "${GREEN}✓ Base de datos importada${NC}"

# 2. Detener WordPress para poder modificar wp-content
echo -e "${YELLOW}Deteniendo WordPress...${NC}"
docker compose stop wordpress

# 3. Restaurar wp-content
# El tar puede contener: (A) carpeta "wp-content" con todo dentro, o (B) directamente plugins/, themes/, uploads/
echo -e "${YELLOW}Restaurando wp-content...${NC}"
WP_TAR_BASENAME="$(basename "$WP_TAR_FILE")"
docker run --rm \
  -v "$VOLUME_WP:/var/www/html" \
  -v "$WP_TAR_FILE:/tmp/wp-import.tar.gz:ro" \
  wordpress:latest \
  sh -c '
    set -e
    cd /var/www/html
    mkdir -p wp-content
    tmpdir=$(mktemp -d)
    tar -xzf /tmp/wp-import.tar.gz -C "$tmpdir"
    # Si el tar tiene una sola carpeta "wp-content", copiar su contenido
    if [ -d "$tmpdir/wp-content" ] && [ ! -d "$tmpdir/plugins" ]; then
      cp -a "$tmpdir/wp-content/." wp-content/
    else
      # Contenido directo de wp-content (plugins, themes, uploads, etc.)
      cp -a "$tmpdir/." wp-content/
    fi
    rm -rf "$tmpdir"
    chown -R www-data:www-data wp-content
  '

# 4. Reiniciar WordPress
echo -e "${YELLOW}Reiniciando WordPress...${NC}"
docker compose start wordpress

echo -e "${GREEN}✓ Importación completada${NC}"
echo ""
echo -e "${YELLOW}Pasos recomendados:${NC}"
echo "  1. Si el sitio antiguo usaba otra URL, actualiza las URLs en la base de datos:"
echo "     docker compose exec wordpress wp search-replace 'https://sitio-antiguo.com' 'http://localhost' --all-tables --allow-root"
echo "     (o instala WP-CLI y ejecuta search-replace con tu dominio actual)"
echo "  2. Ajusta wp-config si es necesario (dominio, claves, etc.)."
echo "  3. Entra al panel de WordPress y revisa enlaces, medios y caché."
echo "  4. Si usas el volumen ./themes para un tema hijo, asegúrate de que siga montado y sincronizado."
