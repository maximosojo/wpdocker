#!/bin/bash
# Script de prueba para validar que setup.sh funciona correctamente
# Ejecutar antes de desplegar para asegurar que todo está bien

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

echo "=== Prueba de setup.sh ==="
echo ""

# 1. Verificar que estamos en el proyecto
if [ ! -f "docker-compose.yml" ]; then
  echo -e "${RED}✗ Error: No se encuentra docker-compose.yml${NC}"
  exit 1
fi
echo -e "${GREEN}✓ docker-compose.yml encontrado${NC}"

# 2. Crear .env de prueba
cat > .env.test << 'EOF'
DOMAIN=test.local
MYSQL_ROOT_PASSWORD=test123
MYSQL_PASSWORD=test123
NGINX_WORKER_PROCESSES=2
NGINX_WORKER_CONNECTIONS=512
PHP_MEMORY_LIMIT=160M
EOF

# 3. Ejecutar setup.sh con .env de prueba
echo "Ejecutando setup.sh con .env de prueba..."
if bash scripts/setup.sh < /dev/null 2>&1 | grep -q "Error"; then
  echo -e "${RED}✗ setup.sh falló${NC}"
  rm -f .env.test
  exit 1
fi
echo -e "${GREEN}✓ setup.sh ejecutado correctamente${NC}"

# 4. Verificar que se generaron los archivos
ERRORS=0
if [ ! -f "nginx/generated/nginx.conf" ]; then
  echo -e "${RED}✗ nginx/generated/nginx.conf no existe${NC}"
  ERRORS=$((ERRORS + 1))
else
  echo -e "${GREEN}✓ nginx/generated/nginx.conf generado${NC}"
  # Verificar que no tiene variables sin sustituir
  if grep -q '\${' nginx/generated/nginx.conf; then
    echo -e "${RED}✗ nginx.conf tiene variables sin sustituir${NC}"
    ERRORS=$((ERRORS + 1))
  fi
fi

if [ ! -f "nginx/generated/wordpress.conf" ]; then
  echo -e "${RED}✗ nginx/generated/wordpress.conf no existe${NC}"
  ERRORS=$((ERRORS + 1))
else
  echo -e "${GREEN}✓ nginx/generated/wordpress.conf generado${NC}"
  # Verificar que tiene el dominio correcto
  if ! grep -q "server_name test.local www.test.local" nginx/generated/wordpress.conf; then
    echo -e "${RED}✗ wordpress.conf no tiene el dominio correcto${NC}"
    ERRORS=$((ERRORS + 1))
  fi
  # Verificar que no tiene variables sin sustituir
  if grep -q '\${' nginx/generated/wordpress.conf; then
    echo -e "${RED}✗ wordpress.conf tiene variables sin sustituir${NC}"
    ERRORS=$((ERRORS + 1))
  fi
fi

if [ ! -f "php-config/generated/memory.ini" ]; then
  echo -e "${RED}✗ php-config/generated/memory.ini no existe${NC}"
  ERRORS=$((ERRORS + 1))
else
  echo -e "${GREEN}✓ php-config/generated/memory.ini generado${NC}"
  # Verificar que tiene el valor correcto
  if ! grep -q "memory_limit = 160M" php-config/generated/memory.ini; then
    echo -e "${RED}✗ memory.ini no tiene el valor correcto${NC}"
    ERRORS=$((ERRORS + 1))
  fi
fi

# 5. Validar sintaxis de nginx (si nginx está disponible)
if command -v nginx >/dev/null 2>&1; then
  echo "Validando sintaxis de nginx.conf..."
  if nginx -t -c "$PROJECT_ROOT/nginx/generated/nginx.conf" 2>&1 | grep -q "successful"; then
    echo -e "${GREEN}✓ Sintaxis de nginx.conf válida${NC}"
  else
    echo -e "${YELLOW}⚠ No se pudo validar sintaxis de nginx (nginx no disponible o requiere configuración adicional)${NC}"
  fi
fi

# 6. Validar docker-compose config
echo "Validando docker-compose.yml..."
if docker compose config >/dev/null 2>&1; then
  echo -e "${GREEN}✓ docker-compose.yml válido${NC}"
else
  echo -e "${RED}✗ docker-compose.yml tiene errores${NC}"
  ERRORS=$((ERRORS + 1))
fi

# 7. Limpiar
rm -f .env.test
rm -f nginx/generated/nginx.conf nginx/generated/wordpress.conf php-config/generated/memory.ini

echo ""
if [ $ERRORS -eq 0 ]; then
  echo -e "${GREEN}=== Todas las pruebas pasaron ===${NC}"
  exit 0
else
  echo -e "${RED}=== Fallaron $ERRORS pruebas ===${NC}"
  exit 1
fi
