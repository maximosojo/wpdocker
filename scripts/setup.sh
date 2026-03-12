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

# Asegurar que los archivos generados existan (usar script de inicialización)
if [ -f "$SCRIPT_DIR/init-generated-files.sh" ]; then
  bash "$SCRIPT_DIR/init-generated-files.sh" >/dev/null 2>&1 || true
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
chmod 755 nginx/generated 2>/dev/null || true

# Si no existe, copiar desde default para que Docker pueda montarlo
if [ ! -f "nginx/generated/nginx.conf" ]; then
  if [ -f "nginx/generated/nginx.conf.default" ]; then
    cp nginx/generated/nginx.conf.default nginx/generated/nginx.conf
  fi
fi

# Eliminar si existe como directorio (usar || true para no fallar si no existe)
if [ -d "nginx/generated/nginx.conf" ]; then
  chmod -R u+w nginx/generated/nginx.conf 2>/dev/null || true
  rm -rf nginx/generated/nginx.conf 2>/dev/null || true
fi

NGINX_WORKERS="${NGINX_WORKER_PROCESSES:-2}"
NGINX_CONNS="${NGINX_WORKER_CONNECTIONS:-512}"
NGINX_KEEPALIVE="${NGINX_UPSTREAM_KEEPALIVE:-64}"
NGINX_OUTPUT="nginx/generated/nginx.conf"

# Exportar variables para envsubst (si está disponible)
export NGINX_WORKER_PROCESSES="$NGINX_WORKERS"
export NGINX_WORKER_CONNECTIONS="$NGINX_CONNS"
export NGINX_UPSTREAM_KEEPALIVE="$NGINX_KEEPALIVE"

# Verificar que podemos escribir en el directorio
if [ ! -w "nginx/generated" ]; then
  echo -e "${RED}Error: No hay permisos de escritura en nginx/generated/${NC}"
  echo "Ejecuta: chmod 755 nginx/generated"
  exit 1
fi

# Eliminar archivo existente antes de generar (asegurar que no sea directorio)
rm -f "$NGINX_OUTPUT" 2>/dev/null || true

if command -v envsubst >/dev/null 2>&1; then
  # Usar envsubst con las variables exportadas
  envsubst '\$NGINX_WORKER_PROCESSES \$NGINX_WORKER_CONNECTIONS \$NGINX_UPSTREAM_KEEPALIVE' < nginx/templates/nginx.conf.template > "$NGINX_OUTPUT"
  if [ $? -ne 0 ]; then
    echo -e "${YELLOW}envsubst falló, usando sed como respaldo${NC}"
    sed -e "s/\${NGINX_WORKER_PROCESSES}/${NGINX_WORKERS}/g" \
        -e "s/\${NGINX_WORKER_CONNECTIONS}/${NGINX_CONNS}/g" \
        -e "s/\${NGINX_UPSTREAM_KEEPALIVE}/${NGINX_KEEPALIVE}/g" \
        nginx/templates/nginx.conf.template > "$NGINX_OUTPUT"
  fi
else
  # Usar sed como respaldo
  sed -e "s/\${NGINX_WORKER_PROCESSES}/${NGINX_WORKERS}/g" \
      -e "s/\${NGINX_WORKER_CONNECTIONS}/${NGINX_CONNS}/g" \
      -e "s/\${NGINX_UPSTREAM_KEEPALIVE}/${NGINX_KEEPALIVE}/g" \
      nginx/templates/nginx.conf.template > "$NGINX_OUTPUT"
fi

# Validar que el archivo generado es válido (no tiene variables sin sustituir)
if grep -q '\${' "$NGINX_OUTPUT" 2>/dev/null; then
  echo -e "${RED}Error: El archivo generado tiene variables sin sustituir${NC}"
  echo "Contenido de la línea problemática:"
  grep '\${' "$NGINX_OUTPUT" | head -3
  exit 1
fi

if [ -f "$NGINX_OUTPUT" ]; then
  chmod 644 "$NGINX_OUTPUT" 2>/dev/null || true
  echo -e "${GREEN}✓ Generado $NGINX_OUTPUT (workers: ${NGINX_WORKERS}, connections: ${NGINX_CONNS}, keepalive: ${NGINX_KEEPALIVE})${NC}"
else
  echo -e "${RED}✗ Error al generar $NGINX_OUTPUT (verifica permisos en nginx/generated/)${NC}"
  exit 1
fi

# Generar wordpress.conf en directorio ignorado (igual que nginx.conf)
WP_OUTPUT="nginx/generated/wordpress.conf"

# Exportar DOMAIN para envsubst
export DOMAIN

# Eliminar archivo existente antes de generar (asegurar que no sea directorio)
rm -f "$WP_OUTPUT" 2>/dev/null || true

if command -v envsubst >/dev/null 2>&1; then
  # Usar envsubst con la variable exportada
  envsubst '\$DOMAIN' < nginx/templates/wordpress.conf.template > "$WP_OUTPUT"
  if [ $? -ne 0 ]; then
    echo -e "${YELLOW}envsubst falló, usando sed como respaldo${NC}"
    sed "s/\${DOMAIN}/$DOMAIN/g" nginx/templates/wordpress.conf.template > "$WP_OUTPUT"
  fi
else
  # Usar sed como respaldo
  sed "s/\${DOMAIN}/$DOMAIN/g" nginx/templates/wordpress.conf.template > "$WP_OUTPUT"
fi

# Validar que el archivo generado es válido (no tiene variables sin sustituir)
if grep -q '\${DOMAIN}' "$WP_OUTPUT" 2>/dev/null; then
  echo -e "${RED}Error: El archivo generado tiene variables sin sustituir${NC}"
  echo "Contenido de la línea problemática:"
  grep '\${DOMAIN}' "$WP_OUTPUT" | head -3
  exit 1
fi

if [ -f "$WP_OUTPUT" ]; then
  chmod 644 "$WP_OUTPUT" 2>/dev/null || true
  echo -e "${GREEN}✓ Generado $WP_OUTPUT (server_name: $DOMAIN www.$DOMAIN)${NC}"
else
  echo -e "${RED}✗ Error al generar $WP_OUTPUT${NC}"
  exit 1
fi

# Generar php-config/generated/memory.ini desde .env (directorio ignorado por Git)
mkdir -p php-config/generated
chmod 755 php-config/generated 2>/dev/null || true

# Si no existe, copiar desde default para que Docker pueda montarlo
PHP_OUTPUT="php-config/generated/memory.ini"
if [ ! -f "$PHP_OUTPUT" ]; then
  if [ -f "php-config/generated/memory.ini.default" ]; then
    cp php-config/generated/memory.ini.default "$PHP_OUTPUT"
  fi
fi

# Eliminar si existe como directorio
if [ -d "$PHP_OUTPUT" ]; then
  chmod -R u+w "$PHP_OUTPUT" 2>/dev/null || true
  rm -rf "$PHP_OUTPUT" 2>/dev/null || true
fi

# Verificar que podemos escribir en el directorio
if [ ! -w "php-config/generated" ]; then
  echo -e "${RED}Error: No hay permisos de escritura en php-config/generated/${NC}"
  echo "Ejecuta: chmod 755 php-config/generated"
  exit 1
fi

PHP_MEM="${PHP_MEMORY_LIMIT:-128M}"
# Asegurar que tenga M al final
case "$PHP_MEM" in
  *M) ;;
  *) PHP_MEM="${PHP_MEM}M" ;;
esac
PHP_MAX_EXEC="${PHP_MAX_EXECUTION_TIME:-300}"
PHP_MAX_VARS="${PHP_MAX_INPUT_VARS:-5000}"
PHP_OUTPUT="php-config/generated/memory.ini"
cat > "$PHP_OUTPUT" << PHPINI
; Generado por setup.sh desde .env (evitar 502/504 en servidores con poca RAM)
memory_limit = $PHP_MEM
max_execution_time = $PHP_MAX_EXEC
max_input_time = $PHP_MAX_EXEC
max_input_vars = $PHP_MAX_VARS
PHPINI
if [ -f "$PHP_OUTPUT" ]; then
  chmod 644 "$PHP_OUTPUT" 2>/dev/null || true
  echo -e "${GREEN}✓ Generado $PHP_OUTPUT (memory_limit=$PHP_MEM, max_execution_time=$PHP_MAX_EXEC)${NC}"
else
  echo -e "${RED}✗ Error al generar $PHP_OUTPUT (verifica permisos en php-config/generated/)${NC}"
  exit 1
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
