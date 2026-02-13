#!/bin/bash
# Genera la configuración de Nginx desde .env y prepara directorios.
# Detecta recursos del sistema y sugiere valores óptimos si no están en .env
# Ejecutar desde la raíz del proyecto. En servidores nuevos: crear .env → ./scripts/setup.sh → docker-compose up -d

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
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

# Detectar recursos si no están definidos en .env
if [ -z "${DOCKER_MYSQL_CPU_LIMIT:-}" ] || [ -z "${DOCKER_MYSQL_MEMORY_LIMIT:-}" ]; then
  echo -e "${BLUE}Detectando recursos del sistema para optimización...${NC}"
  if [ -f "$SCRIPT_DIR/detect-resources.sh" ]; then
    DETECTED_VARS=$("$SCRIPT_DIR/detect-resources.sh" 2>/dev/null | grep "^DOCKER_\|^MYSQL_\|^PHP_\|^NGINX_" || true)
    if [ -n "$DETECTED_VARS" ]; then
      echo -e "${YELLOW}Valores recomendados según recursos del sistema:${NC}"
      echo "$DETECTED_VARS" | head -15
      echo ""
      echo -e "${YELLOW}Puedes agregar estos valores a .env o usar los valores por defecto (optimizados para servidor pequeño).${NC}"
      echo ""
    fi
  fi
fi

# Verificar que los templates de Nginx existan
if [ ! -f "nginx/templates/nginx.conf.template" ] || [ ! -f "nginx/templates/wordpress.conf.template" ]; then
  echo -e "${RED}Error: Los templates de Nginx deben estar en nginx/templates/${NC}"
  exit 1
fi

# Generar nginx.conf en directorio ignorado (nginx.conf principal no se procesa automáticamente)
mkdir -p nginx/generated
# Eliminar si existe como directorio o archivo
[ -d "nginx/generated/nginx.conf" ] && rm -rf nginx/generated/nginx.conf
[ -f "nginx/generated/nginx.conf" ] && rm -f nginx/generated/nginx.conf

NGINX_WORKERS="${NGINX_WORKER_PROCESSES:-2}"
NGINX_CONNS="${NGINX_WORKER_CONNECTIONS:-512}"
if command -v envsubst >/dev/null 2>&1; then
  envsubst '\$NGINX_WORKER_PROCESSES \$NGINX_WORKER_CONNECTIONS' < nginx/templates/nginx.conf.template > nginx/generated/nginx.conf
else
  sed -e "s/\${NGINX_WORKER_PROCESSES}/${NGINX_WORKERS}/g" \
      -e "s/\${NGINX_WORKER_CONNECTIONS}/${NGINX_CONNS}/g" \
      nginx/templates/nginx.conf.template > nginx/generated/nginx.conf
fi
echo -e "${GREEN}✓ Generado nginx/generated/nginx.conf (workers: ${NGINX_WORKERS}, connections: ${NGINX_CONNS})${NC}"

# wordpress.conf se procesa automáticamente por el contenedor desde nginx/templates/
# Las variables se pasan vía environment en docker-compose.yml
echo -e "${GREEN}✓ Template wordpress.conf listo (se procesa automáticamente en el contenedor)${NC}"
echo -e "${BLUE}  Variable DOMAIN=${DOMAIN} se usará en el contenedor${NC}"

# Generar php-config/generated/memory.ini desde .env (directorio ignorado por Git)
mkdir -p php-config/generated
# Eliminar si existe como directorio o archivo
[ -d "php-config/generated/memory.ini" ] && rm -rf php-config/generated/memory.ini
[ -f "php-config/generated/memory.ini" ] && rm -f php-config/generated/memory.ini

PHP_MEM="${PHP_MEMORY_LIMIT:-128M}"
# Asegurar que tenga M al final
case "$PHP_MEM" in
  *M) ;;
  *) PHP_MEM="${PHP_MEM}M" ;;
esac
cat > php-config/generated/memory.ini << PHPINI
; Generado por setup.sh - memory_limit desde .env (evitar 502/504 en servidores con poca RAM)
memory_limit = $PHP_MEM
PHPINI
echo -e "${GREEN}✓ Generado php-config/generated/memory.ini (memory_limit=$PHP_MEM)${NC}"

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

# Verificar recursos configurados
echo ""
echo -e "${BLUE}Resumen de recursos configurados:${NC}"
echo "  MySQL:   CPU ${DOCKER_MYSQL_CPU_LIMIT:-0.8} | RAM ${DOCKER_MYSQL_MEMORY_LIMIT:-360M}"
echo "  WordPress: CPU ${DOCKER_WP_CPU_LIMIT:-0.8} | RAM ${DOCKER_WP_MEMORY_LIMIT:-300M}"
echo "  Nginx:   CPU ${DOCKER_NGINX_CPU_LIMIT:-0.5} | RAM ${DOCKER_NGINX_MEMORY_LIMIT:-80M}"
echo ""
echo -e "${GREEN}Configuración lista. Para arrancar los servicios:${NC}"
echo "  docker-compose up -d"
echo ""
echo "Para ver logs: docker-compose logs -f"
echo ""
echo -e "${YELLOW}Tip: Si experimentas problemas de rendimiento, ejecuta ./scripts/detect-resources.sh${NC}"
echo -e "${YELLOW}     y ajusta los valores DOCKER_* y MYSQL_* en .env según las recomendaciones.${NC}"
